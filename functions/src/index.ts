import { createHash } from "crypto";
import * as logger from "firebase-functions/logger";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

// jose は JWS/JWT 検証に使用（Appleの署名検証で必須）
import { decodeProtectedHeader, importX509, jwtVerify } from "jose";

initializeApp();
const db = getFirestore();

/**
 * --- 設計メモ ---
 * entitlements: users/{uid}/entitlements/current
 * usageDaily:   users/{uid}/usageDaily/{yyyy-MM-dd}
 * usageMonthly: users/{uid}/usageMonthly/{yyyy-MM}
 */

type Plan =
  | "free"
  | "lifetime"
  | "subscription_monthly"
  | "subscription_yearly";

type ConsumeOp = "reformulate" | "empathy";

/** iOS側の ProductID と一致させる */
const ProductID = {
  premiumMonthly: "gokigen.premium.monthly",
  premiumYearly: "gokigen.premium.yearly",
  lifetime: "gokigen.lifetime",
} as const;

/** 回数制限（P1A） */
const Limits = {
  freeDaily: 10,
  lifetimeMonthly: 200,
} as const;

/**
 * ピン（必須）：Apple の中間 or ルート証明書の SHA256 を2本以上登録（ローテ対策）。
 * 下の値はプレースホルダー。Sandbox で購入/復元 → Cloud Logs の "x5c sha256 =" で [1][2] を取得し、
 * 必ず実データに差し替える。差し替えずデプロイすると全 JWS が弾かれる。本番リリース前は本番レシートでもログを取り追加すること。
 */
const APPLE_CERT_PINNED_SHA256: Set<string> = new Set([
  "0000000000000000000000000000000000000000000000000000000000000001", // 要差し替え: ログ x5c sha256 [1] の64桁hex
  "0000000000000000000000000000000000000000000000000000000000000002", // 要差し替え: ログ x5c sha256 [2] の64桁hex
]);

/** 証明書ユーティリティ（x5c ピン留め用） */
function b64ToDer(b64: string): Buffer {
  return Buffer.from(b64, "base64");
}

function derToPem(der: Buffer): string {
  const b64 = der.toString("base64");
  const lines = b64.match(/.{1,64}/g) ?? [];
  return `-----BEGIN CERTIFICATE-----\n${lines.join("\n")}\n-----END CERTIFICATE-----\n`;
}

function sha256Hex(data: Buffer): string {
  return createHash("sha256").update(data).digest("hex");
}

/** Utilities */
function assertAuthed(context: any): string {
  const uid = context.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  return uid;
}

function pad2(n: number) {
  return n < 10 ? `0${n}` : `${n}`;
}

function dayKeyJST(now = new Date()): string {
  // まずは単純にサーバー時刻UTCを使う（P1BでJST厳密化してもOK）
  // JST基準にしたいなら +9h して日付を切る。
  const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  return `${jst.getUTCFullYear()}-${pad2(jst.getUTCMonth() + 1)}-${pad2(jst.getUTCDate())}`;
}

function monthKeyJST(now = new Date()): string {
  const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  return `${jst.getUTCFullYear()}-${pad2(jst.getUTCMonth() + 1)}`;
}

/** 秒（10桁）ならミリ秒に変換。effectiveUntil は常に ms で保存・比較する */
function normalizeToMs(epoch: number): number {
  if (epoch < 1_000_000_000_000) {
    return epoch * 1000;
  }
  return epoch;
}

/**
 * Apple JWS(Transaction) の検証：署名検証 + x5c ピン留め（偽証明書で抜かれない）。
 * (A) JWS 署名が正しい (B) 署名鍵が Apple の証明書チェーン由来 → 両方満たすときだけ payload を返す。
 */
async function verifyAppleTransactionJWS(jws: string): Promise<any> {
  // 1) header から x5c を取得
  const header = decodeProtectedHeader(jws);
  const x5c = (header as any).x5c as string[] | undefined;
  if (!x5c || x5c.length === 0) {
    throw new HttpsError("failed-precondition", "Missing x5c in JWS header.");
  }

  // 2) x5c を DER にして fingerprint を取る
  // x5c[0]=leaf, x5c[1]=intermediate, x5c[2]=root のことが多い（常に保証ではない）
  const ders = x5c.map(b64ToDer);
  const pins = ders.map(sha256Hex);

  // 3) Apple pinned cert（Intermediate/Root）の一致チェック（チート防止の核心）
  const matched = pins.some((p) => APPLE_CERT_PINNED_SHA256.has(p));
  if (!matched) {
    throw new HttpsError(
      "permission-denied",
      "Certificate chain is not trusted (pin mismatch)."
    );
  }

  // 4) leaf cert の public key で署名検証
  const leafPem = derToPem(ders[0]);
  const key = await importX509(leafPem, "ES256");

  const { payload } = await jwtVerify(jws, key, {
    // issuer / audience は Apple 側クレーム仕様に合わせて必要なら入れる
    // P1A では「署名検証 + pin」で十分な防御になる
  });

  return payload;
}

/** サブスクかどうか（期限チェック対象） */
function isSubscription(productId: string): boolean {
  return (
    productId === ProductID.premiumMonthly || productId === ProductID.premiumYearly
  );
}

/**
 * payload から plan を決める（優先: lifetime > yearly > monthly > free）
 * payload の形式は StoreKit2 Transaction の claim を想定
 */
function resolvePlanFromOwnedProducts(owned: Set<string>): Plan {
  if (owned.has(ProductID.lifetime)) return "lifetime";
  if (owned.has(ProductID.premiumYearly)) return "subscription_yearly";
  if (owned.has(ProductID.premiumMonthly)) return "subscription_monthly";
  return "free";
}

/**
 * entitlements/current を読む（無ければ free）。effectiveUntil は常に ms で返す（読む側で正規化）。
 */
async function getCurrentPlan(
  uid: string
): Promise<{ plan: Plan; effectiveUntil: number | null }> {
  const ref = db.doc(`users/${uid}/entitlements/current`);
  const snap = await ref.get();
  if (!snap.exists) return { plan: "free", effectiveUntil: null };
  const data = snap.data() as any;
  const rawUntil = data?.effectiveUntil;
  // 無効値（null/""/0/NaN）は期限なしにしない。subscription は consumeRewrite で null なら free に倒す。
  let effectiveUntil: number | null = null;
  if (rawUntil != null && rawUntil !== undefined && rawUntil !== "") {
    const n = Number(rawUntil);
    if (n !== 0 && Number.isFinite(n)) {
      effectiveUntil = normalizeToMs(n);
    }
  }
  return {
    plan: (data?.plan as Plan) ?? "free",
    effectiveUntil,
  };
}

/**
 * 1) syncEntitlements
 * iOSから Transaction.jwsRepresentation[] を渡す
 * サーバーで検証して entitlements/current を更新
 */
export const syncEntitlements = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = assertAuthed(request);

    const transactions = request.data?.transactions as string[] | undefined;
    if (!Array.isArray(transactions) || transactions.length === 0) {
      throw new HttpsError("invalid-argument", "transactions[] is required.");
    }
    logger.info("syncEntitlements", {
      uid,
      transactionsCount: transactions.length,
    });

    // accepted: revocation なし & productId あり。有効期限は per-product で保持。
    const acceptedExpiry = new Map<string, number | null>(); // productId -> effectiveUntilMs (null = lifetime)
    let verifiedJwsCount = 0;

    for (const jws of transactions) {
      try {
        // ピン値取得用（pin確定用ログ。運用では別ログで見る）
        const header = decodeProtectedHeader(jws);
        const x5c = (header as any).x5c as string[] | undefined;
        if (x5c?.length) {
          const ders = x5c.map((b) => Buffer.from(b, "base64"));
          const fps = ders.map((d) => createHash("sha256").update(d).digest("hex"));
          logger.info("x5c sha256 =", fps);
        }

        const payload = await verifyAppleTransactionJWS(jws);
        verifiedJwsCount += 1;

        const productId = payload?.productId ?? payload?.productID;
        const revocationDate = payload?.revocationDate;
        const expiresDate = payload?.expiresDate;

        if (!productId) continue;
        if (revocationDate) continue;

        const pid = String(productId);
        if (pid === ProductID.lifetime) {
          acceptedExpiry.set(pid, null);
        } else if (isSubscription(pid) && expiresDate != null) {
          const n = normalizeToMs(Number(expiresDate));
          if (Number.isFinite(n)) {
            const cur = acceptedExpiry.get(pid);
            const prev = cur !== undefined && cur !== null ? cur : n;
            acceptedExpiry.set(pid, Math.max(prev, n));
          } else {
            acceptedExpiry.set(pid, acceptedExpiry.get(pid) ?? null);
          }
        } else {
          acceptedExpiry.set(pid, acceptedExpiry.get(pid) ?? null);
        }
      } catch (e: any) {
        logger.warn("syncEntitlements: verify failed for one transaction", e?.message ?? e);
        continue;
      }
    }

    const nowMs = Date.now();
    const activeProductIds = new Set<string>();
    let effectiveUntilMs: number | null = null;
    for (const [pid, until] of acceptedExpiry) {
      if (until === null) {
        activeProductIds.add(pid);
      } else {
        if (until > nowMs) {
          activeProductIds.add(pid);
          if (effectiveUntilMs === null || until > effectiveUntilMs) {
            effectiveUntilMs = until;
          }
        }
      }
    }

    const acceptedCount = acceptedExpiry.size;
    const activeCount = activeProductIds.size;
    const activeProductIDs = Array.from(activeProductIds);
    const ref = db.doc(`users/${uid}/entitlements/current`);

    // 運用用ログ（件数＋先頭数件で短く）
    const logPayload = {
      uid,
      transactionsCount: transactions.length,
      verifiedJwsCount,
      acceptedCount,
      activeCount,
      plan: activeCount > 0 ? resolvePlanFromOwnedProducts(activeProductIds) : "free",
      effectiveUntilMs: effectiveUntilMs ?? undefined,
      ownedCount: activeProductIDs.length,
      ownedSample: activeProductIDs.slice(0, 3),
    };

    // 署名検証が1件も通っていない → 更新しない（pin/認証/通信の問題）
    if (verifiedJwsCount === 0) {
      logger.warn("syncEntitlements: no verified JWS, skipping update", {
        ...logPayload,
        reason: "no_verified_jws",
      });
      return { ok: false };
    }

    // 検証は通ったが現在有効な権利が0件（解約/返金/期限切れのみ）→ free に更新
    if (activeCount === 0) {
      await ref.set(
        {
          plan: "free",
          ownedProductIDs: [],
          effectiveUntil: null,
          updatedAt: FieldValue.serverTimestamp(),
          source: "storekit2_jws",
          lastSyncReason: "no_accepted_products",
        },
        { merge: true }
      );
      logger.info("syncEntitlements: updated to free", {
        ...logPayload,
        reason: "no_accepted_products",
      });
      return { ok: true, plan: "free", effectiveUntil: null, ownedProductIDs: [] };
    }

    const plan = resolvePlanFromOwnedProducts(activeProductIds);
    await ref.set(
      {
        plan,
        ownedProductIDs: activeProductIDs,
        effectiveUntil: effectiveUntilMs,
        updatedAt: FieldValue.serverTimestamp(),
        source: "storekit2_jws",
      },
      { merge: true }
    );

    logger.info("syncEntitlements: updated", {
      ...logPayload,
      plan,
      effectiveUntilMs: effectiveUntilMs ?? undefined,
      reason: "ok",
    });
    return { ok: true, plan, effectiveUntil: effectiveUntilMs, ownedProductIDs: activeProductIDs };
  }
);

/**
 * 2) consumeRewrite
 * AIを叩く直前に必ず呼ぶ
 * - entitlements/current を見て plan を確定
 * - usageDaily / usageMonthly を transaction でインクリメント（allowed の時だけ）
 */
export const consumeRewrite = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = assertAuthed(request);

    const op = request.data?.op as ConsumeOp | undefined;
    if (op !== "reformulate" && op !== "empathy") {
      throw new HttpsError("invalid-argument", "op must be 'reformulate' or 'empathy'.");
    }

    const { plan, effectiveUntil } = await getCurrentPlan(uid);

    // サブスクは「状態」で判定。期限切れ or 無効な effectiveUntil なら free に落とす
    let actualPlan: Plan = plan;
    let subscriptionDenyReason: string | null = null;
    if (plan === "subscription_monthly" || plan === "subscription_yearly") {
      if (effectiveUntil == null || effectiveUntil === 0) {
        actualPlan = "free";
        subscriptionDenyReason = "missing_until";
      } else {
        const nowMs = Date.now();
        if (effectiveUntil < nowMs) {
          actualPlan = "free";
        }
      }
    }

    // 無制限（有効なサブスクのみ）
    if (
      actualPlan === "subscription_monthly" ||
      actualPlan === "subscription_yearly"
    ) {
      return {
        allowed: true,
        plan: actualPlan,
        limit: null,
        used: null,
        remaining: null,
        resetKey: null,
        reason: "active_subscription",
      };
    }

    const now = new Date();

    if (actualPlan === "free") {
      const key = dayKeyJST(now);
      const ref = db.doc(`users/${uid}/usageDaily/${key}`);

      const result = await db.runTransaction(async (txn) => {
        const snap = await txn.get(ref);
        const used = (snap.exists ? (snap.data() as any).rewriteUsed : 0) ?? 0;

        if (used >= Limits.freeDaily) {
          return {
            allowed: false,
            plan: actualPlan,
            limit: Limits.freeDaily,
            used,
            remaining: 0,
            resetKey: key,
            reason: "quota_exceeded",
            paywall: true,
          };
        }

        txn.set(
          ref,
          {
            rewriteUsed: used + 1,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        return {
          allowed: true,
          plan: actualPlan,
          limit: Limits.freeDaily,
          used: used + 1,
          remaining: Math.max(0, Limits.freeDaily - (used + 1)),
          resetKey: key,
          reason: subscriptionDenyReason ?? "free_daily",
        };
      });

      return result;
    }

    // lifetime（月次制限）
    if (actualPlan === "lifetime") {
      const key = monthKeyJST(now);
      const ref = db.doc(`users/${uid}/usageMonthly/${key}`);

      const result = await db.runTransaction(async (txn) => {
        const snap = await txn.get(ref);
        const used = (snap.exists ? (snap.data() as any).rewriteUsed : 0) ?? 0;

        if (used >= Limits.lifetimeMonthly) {
          return {
            allowed: false,
            plan: actualPlan,
            limit: Limits.lifetimeMonthly,
            used,
            remaining: 0,
            resetKey: key,
            reason: "quota_exceeded",
            paywall: true,
          };
        }

        txn.set(
          ref,
          {
            rewriteUsed: used + 1,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        return {
          allowed: true,
          plan: actualPlan,
          limit: Limits.lifetimeMonthly,
          used: used + 1,
          remaining: Math.max(0, Limits.lifetimeMonthly - (used + 1)),
          resetKey: key,
        };
      });

      return result;
    }

    // ここに来るなら free 扱いに倒す（安全側）
    return {
      allowed: false,
      plan: "free",
      reason: "plan_unknown",
      paywall: true,
    };
  }
);
