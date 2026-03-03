import { createHash } from "crypto";
import * as logger from "firebase-functions/logger";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

// jose は JWS/JWT 検証に使用（Appleの署名検証で必須）
import { decodeProtectedHeader, importX509, jwtVerify } from "jose";

import { consumeAiLimits, getCurrentDetails, tierForServerPlan, type AiOp } from "./rateLimit";
import { enqueueLineStopperJob, enqueueAiJob as enqueueAiJobTask, type AiJobOp } from "./tasks";

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

/** 入力文字数上限（コスト防衛）。無料 400 / 有料 800。サーバーで強制トリム（クライアントを信用しない） */
const MAX_CHARS_FREE = 400;
const MAX_CHARS_PAID = 800;
/** 言い換え・危険度以外（共感など）は固定 */
const MAX_CHARS = {
  lineStopper: 600, // 旧値・参照時は getMaxCharsLineStopper(plan) を優先
  reformulate: 400, // 旧値・参照時は getMaxCharsReformulate(plan) を優先
  empathy: 800,
} as const;

function getMaxCharsReformulate(plan: Plan): number {
  return plan === "free" ? MAX_CHARS_FREE : MAX_CHARS_PAID;
}
function getMaxCharsLineStopper(plan: Plan): number {
  return plan === "free" ? MAX_CHARS_FREE : MAX_CHARS_PAID;
}

function clampText(s: string | null | undefined, maxChars: number): string {
  const t = String(s ?? "").trim();
  if (t.length <= maxChars) return t;
  return t.slice(0, maxChars);
}

/** Gemini 出力トークン上限。無料 750 / 有料 900。 */
const MAX_OUTPUT_TOKENS_FREE = 750;
const MAX_OUTPUT_TOKENS_PAID = 900;
const MAX_OUTPUT_TOKENS = {
  lineStopper: 900,
  reformulate: 900,
  empathy: 220,
} as const;

function getMaxOutputTokensReformulate(plan: Plan): number {
  return plan === "free" ? MAX_OUTPUT_TOKENS_FREE : MAX_OUTPUT_TOKENS_PAID;
}
function getMaxOutputTokensLineStopper(plan: Plan): number {
  return plan === "free" ? MAX_OUTPUT_TOKENS_FREE : MAX_OUTPUT_TOKENS_PAID;
}

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

const FREE_TRIAL_DAYS_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * 無料ユーザーは初回7日間のみ利用可。8日目以降は課金必須。
 */
async function assertFreeTrialOrPaid(uid: string, actualPlan: Plan): Promise<void> {
  if (actualPlan !== "free") return;
  const userRef = db.doc(`users/${uid}`);
  const snap = await userRef.get();
  const now = Date.now();
  let createdAtMs: number;
  if (!snap.exists) {
    await userRef.set({ createdAt: FieldValue.serverTimestamp(), version: 1 }, { merge: true });
    createdAtMs = now;
  } else {
    const data = snap.data() as { createdAt?: { toMillis?: () => number } } | undefined;
    const created = data?.createdAt as { toMillis?: () => number } | undefined;
    createdAtMs = created?.toMillis?.() ?? now;
  }
  if (now - createdAtMs > FREE_TRIAL_DAYS_MS) {
    throw new HttpsError(
      "failed-precondition",
      "無料お試しは7日間までです。続けてご利用の場合はプレミアムをご検討ください。",
      { code: "free_trial_ended" }
    );
  }
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
      return {
        ok: false,
        plan: "free",
        ownedProductIDs: [],
        effectiveUntil: null,
        reason: "no_verified_jws",
        verifiedJwsCount,
        acceptedCount,
        activeCount,
      };
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
      return {
        ok: true,
        plan: "free",
        effectiveUntil: null,
        ownedProductIDs: [],
        queueTier: "standard",
        reason: "no_accepted_products",
        verifiedJwsCount,
        acceptedCount,
        activeCount,
      };
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
    return {
      ok: true,
      plan,
      effectiveUntil: effectiveUntilMs,
      ownedProductIDs: activeProductIDs,
      queueTier: tierForServerPlan(plan),
      reason: "ok",
      verifiedJwsCount,
      acceptedCount,
      activeCount,
    };
  }
);

/**
 * 2) consumeRewrite（読取のみ）。加算は reformulate/empathy 呼び出し時の consumeAiLimits で行う。
 * 返却は RateLimitDetails に揃え、iOS で共通表示できるようにする。
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
    let actualPlan: Plan = plan;
    if (plan === "subscription_monthly" || plan === "subscription_yearly") {
      if (effectiveUntil == null || effectiveUntil === 0 || effectiveUntil < Date.now()) {
        actualPlan = "free";
      }
    }

    return await getCurrentDetails(uid, actualPlan, op as AiOp);
  }
);

/**
 * 3) consumeLineStopper
 * 地雷LINEストッパー用: ユーザー単位で 1分あたり N回まで（RPM超過の最終防衛）
 * Firestore: quota/{uid} { windowStart, count }
 */
const LINE_STOPPER_LIMIT_PER_MIN = 4;

export const consumeLineStopper = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = assertAuthed(request);

    const ref = db.collection("quota").doc(uid);
    const now = Timestamp.now();
    const nowMs = now.toMillis();

    await db.runTransaction(async (txn) => {
      const snap = await txn.get(ref);
      const doc = snap.exists ? snap.data() : null;

      const windowStartMs = doc?.windowStart?.toMillis?.() ?? 0;
      const count = (doc?.count ?? 0) as number;

      const inSameWindow = nowMs - windowStartMs < 60_000;

      if (!doc || !inSameWindow) {
        txn.set(ref, { windowStart: now, count: 1 }, { merge: true });
        return;
      }

      if (count >= LINE_STOPPER_LIMIT_PER_MIN) {
        throw new HttpsError("resource-exhausted", "rate limited");
      }

      txn.update(ref, { count: count + 1 });
    });

    return { ok: true };
  }
);

/**
 * enqueueLineStopper: 年額は同期実行（キュースキップ）、それ以外は jobs + Cloud Tasks で非同期。
 * 返却: yearly → { status: "DONE", mode: "sync", queueTier, result }; 他 → { status: "QUEUED", mode: "queued", queueTier, jobId }
 */
export const enqueueLineStopper = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = assertAuthed(request);
    const { plan, effectiveUntil } = await getCurrentPlan(uid);
    let actualPlan: Plan = plan;
    if (plan === "subscription_monthly" || plan === "subscription_yearly") {
      if (effectiveUntil == null || effectiveUntil === 0 || effectiveUntil < Date.now()) {
        actualPlan = "free";
      }
    }
    await assertFreeTrialOrPaid(uid, actualPlan);

    const maxChars = getMaxCharsLineStopper(actualPlan);
    const text = clampText(request.data?.text, maxChars);
    logger.info("enqueueLineStopper.entry", { uid: uid.slice(0, 8), textLength: text?.length ?? 0 });
    if (!text) throw new HttpsError("invalid-argument", "text is required");

    const limits = await consumeAiLimits(uid, actualPlan, "lineStopper");
    if (!limits.allowed) {
      throw new HttpsError("resource-exhausted", limits.reason ?? "resource-exhausted", limits);
    }

    const queueTier = limits.tier;

    // 年額は同期で完了（キューをスキップ）
    if (actualPlan === "subscription_yearly") {
      const result = await runLineStopperSync(text, actualPlan);
      return { status: "DONE", mode: "sync", queueTier, result, limits };
    }

    // それ以外は enqueue（jobs + tasks）。TASKS_OIDC_SERVICE_ACCOUNT 未設定時は同期フォールバック
    const jobRef = db.collection("jobs").doc();
    const jobId = jobRef.id;

    await jobRef.set({
      uid,
      plan: actualPlan,
      status: "QUEUED",
      createdAt: FieldValue.serverTimestamp(),
      queueTier,
      textPreview: text.slice(0, 60),
    });

    let taskName = "";
    try {
      taskName = await enqueueLineStopperJob({ jobId, uid, plan: actualPlan, text, queueTier });
    } catch (e) {
      logger.warn("enqueueLineStopperJob failed (e.g. TASKS_OIDC_SERVICE_ACCOUNT not set), falling back to sync", e);
      const result = await runLineStopperSync(text, actualPlan);
      await jobRef.set(
        {
          status: "DONE",
          finishedAt: FieldValue.serverTimestamp(),
          result: { ...result, queueTier },
        },
        { merge: true }
      );
      return { status: "DONE", mode: "sync", queueTier, result, limits };
    }

    await jobRef.set({ taskName }, { merge: true });
    return { status: "QUEUED", mode: "queued", tier: limits.tier, queueTier, jobId, limits };
  }
);

const AI_JOB_OPS: AiJobOp[] = ["lineStopper", "rewrite", "empathy"];

/**
 * enqueueAiJob: 3機能共通のキュー投入（lineStopper / rewrite / empathy）
 * レート制限消費 → jobs 作成 → Cloud Tasks 投入 → jobId 返却
 */
export const enqueueAiJob = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = assertAuthed(request);

    const op = request.data?.op as string | undefined;
    if (!op || !AI_JOB_OPS.includes(op as AiJobOp)) {
      throw new HttpsError("invalid-argument", "op must be one of: lineStopper, rewrite, empathy");
    }

    const maxChars =
      op === "lineStopper"
        ? MAX_CHARS.lineStopper
        : op === "rewrite"
          ? MAX_CHARS.reformulate
          : MAX_CHARS.empathy;
    const text = clampText(request.data?.text, maxChars);
    if (!text) throw new HttpsError("invalid-argument", "text is required");

    const context = request.data?.context as Record<string, unknown> | undefined;

    const { plan, effectiveUntil } = await getCurrentPlan(uid);
    let actualPlan: Plan = plan;
    if (plan === "subscription_monthly" || plan === "subscription_yearly") {
      if (effectiveUntil == null || effectiveUntil === 0 || effectiveUntil < Date.now()) {
        actualPlan = "free";
      }
    }

    const aiOp: AiOp = op === "rewrite" ? "reformulate" : op === "lineStopper" ? "lineStopper" : "empathy";
    const limits = await consumeAiLimits(uid, actualPlan, aiOp);
    if (!limits.allowed) {
      throw new HttpsError("resource-exhausted", limits.reason ?? "resource-exhausted", limits);
    }

    const queueTier = limits.tier;

    const jobRef = db.collection("jobs").doc();
    const jobId = jobRef.id;

    await jobRef.set({
      uid,
      plan: actualPlan,
      op,
      status: "QUEUED",
      createdAt: FieldValue.serverTimestamp(),
      queueTier,
      textPreview: text.slice(0, 60),
    });

    let taskName = "";
    try {
      taskName = await enqueueAiJobTask({
        jobId,
        uid,
        plan: actualPlan,
        op: op as AiJobOp,
        text,
        context,
        queueTier,
      });
    } catch (e) {
      logger.error("enqueueAiJob task failed", e);
      await jobRef.set({ status: "FAILED", error: "ENQUEUE_FAILED" }, { merge: true });
      throw new HttpsError("internal", "enqueue failed");
    }

    await jobRef.set({ taskName }, { merge: true });
    return { jobId, status: "QUEUED", tier: limits.tier, limits };
  }
);

/**
 * getJobResult: jobs/{jobId} の status / result / error を返す（所有者のみ）
 */
export const getJobResult = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = assertAuthed(request);
    const jobId = String(request.data?.jobId ?? "").trim();
    logger.info("getJobResult.entry", { uid: uid.slice(0, 8), jobId: jobId.slice(0, 8) });
    if (!jobId) throw new HttpsError("invalid-argument", "jobId is required");

    const snap = await db.collection("jobs").doc(jobId).get();
    if (!snap.exists) throw new HttpsError("not-found", "job not found");

    const data = snap.data()!;
    if (data.uid !== uid) throw new HttpsError("permission-denied", "not yours");

    return {
      status: data.status ?? "UNKNOWN",
      result: data.result ?? null,
      error: data.error ?? null,
      queueTier: data.queueTier ?? "standard",
    };
  }
);

// --- 地雷LINEストッパー: Functions で Gemini を叩く（キーはサーバのみ・RPM はサーバで握る） ---

const LINE_STOPPER_RPM = 4;
const GEMINI_MODEL = "gemini-2.5-flash";

type LineStopperResponse = {
  risk: "LOW" | "MEDIUM" | "HIGH";
  oneLiner: string;
  suggestions: { label: string; text: string }[];
};

function buildLineStopperPrompt(inputText: string): string {
  return `
あなたは「送信前LINEチェック」専用の文章コーチです。
入力文を評価し、後悔リスクと、コピペ可能な改善案を3つ出します。

【入力文】
${inputText}

【出力ルール（最重要）】
- 出力はJSON 1個だけ。前後に説明文・挨拶・コードフェンス・改行コメントを一切付けない。
- JSONのキーは risk, oneLiner, suggestions のみ（この3つ以外を出さない）
- risk は "LOW" / "MEDIUM" / "HIGH" のいずれか（必ず大文字）
- oneLiner は40文字以内の日本語1文（必須）
- suggestions は要素3個ちょうど（label/text必須）
- label は10文字以内、text は1〜2文でコピペ可能、日本語、敬語寄り
- 文字列は必ずダブルクォート
- 末尾にカンマを付けない
- JSON以外の文字を一切出力しない

{"risk":"LOW","oneLiner":"...","suggestions":[{"label":"...","text":"..."},{"label":"...","text":"..."},{"label":"...","text":"..."}]}
`.trim();
}

function lineStopperRateLimit(uid: string): Promise<void> {
  const ref = db.collection("quota").doc(uid);
  const now = Timestamp.now();
  const nowMs = now.toMillis();

  return db.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    const doc = snap.exists ? snap.data() : null;

    const windowStartMs = (doc?.windowStart as { toMillis?: () => number })?.toMillis?.() ?? 0;
    const count = (doc?.count ?? 0) as number;

    const inSameWindow = nowMs - windowStartMs < 60_000;

    if (!doc || !inSameWindow) {
      txn.set(ref, { windowStart: now, count: 1 }, { merge: true });
      return;
    }

    if (count >= LINE_STOPPER_RPM) {
      throw new HttpsError("resource-exhausted", "rate limited");
    }

    txn.update(ref, { count: count + 1 });
  });
}

function safeFallbackLineStopper(_input: string): LineStopperResponse {
  return {
    risk: "LOW",
    oneLiner: "送信前に一度確認してみましょう。",
    suggestions: [
      { label: "柔らかく", text: "ちょっと気になってることがあるんだけど、時間あるときに話せる？" },
      { label: "余裕", text: "無理しなくて大丈夫だから、落ち着いたら連絡もらえると嬉しいな" },
      { label: "距離", text: "一旦この話は置いておくね。またタイミング合うときに話そう" },
    ],
  };
}

/** 危険度チェックを同期実行（Gemini 呼び出し or フォールバック）。年額・enqueue 失敗フォールバックで共通利用 */
async function runLineStopperSync(text: string, plan: Plan = "free"): Promise<LineStopperResponse> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    logger.warn("GEMINI_API_KEY not set, lineStopper fallback");
    return safeFallbackLineStopper(text);
  }
  const maxOutputTokens = getMaxOutputTokensLineStopper(plan);
  try {
    const prompt = buildLineStopperPrompt(text);
    const raw = await callGeminiText(prompt, apiKey, 0.2, maxOutputTokens);
    const jsonStr = extractBraceBlock(raw) ?? raw.trim();
    const obj = JSON.parse(jsonStr) as unknown;
    return sanitizeAndForceLineStopper(obj);
  } catch (e) {
    logger.warn("runLineStopperSync failed", e);
    return safeFallbackLineStopper(text);
  }
}

function extractBraceBlock(raw: string): string | null {
  let inString = false;
  let escape = false;
  let depth = 0;
  let start = -1;

  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];

    if (escape) {
      escape = false;
      continue;
    }
    if (c === "\\") {
      if (inString) escape = true;
      continue;
    }
    if (c === '"') {
      inString = !inString;
      continue;
    }

    if (!inString) {
      if (c === "{") {
        if (depth === 0) start = i;
        depth++;
      } else if (c === "}") {
        depth--;
        if (depth === 0 && start !== -1) return raw.slice(start, i + 1);
      }
    }
  }
  return null;
}

function sanitizeAndForceLineStopper(jsonObj: unknown): LineStopperResponse {
  const o = jsonObj as Record<string, unknown> | null | undefined;
  const riskRaw = String(o?.risk ?? "LOW").toUpperCase();
  const risk: "LOW" | "MEDIUM" | "HIGH" =
    riskRaw === "HIGH" || riskRaw === "MEDIUM" || riskRaw === "LOW" ? riskRaw : "LOW";

  const oneLiner =
    String((o?.oneLiner as string) ?? "").trim() || "送信前に一度確認してみましょう。";

  let suggestions = Array.isArray(o?.suggestions) ? (o.suggestions as unknown[]) : [];
  suggestions = suggestions
    .slice(0, 3)
    .map((s: unknown) => {
      const t = s as Record<string, unknown>;
      return {
        label: String(t?.label ?? "").trim(),
        text: String(t?.text ?? "").trim(),
      };
    })
    .filter((s: { label: string; text: string }) => s.label && s.text);

  if (suggestions.length < 3) {
    return safeFallbackLineStopper("");
  }

  return { risk, oneLiner, suggestions: suggestions as { label: string; text: string }[] };
}

type CallGeminiTextOptions = {
  responseMimeType?: "text/plain" | "application/json";
  responseSchema?: unknown;
};

/** Gemini 汎用テキスト生成。maxOutputTokens は必須。opts で JSON 出力・スキーマを指定可能。 */
async function callGeminiText(
  prompt: string,
  apiKey: string,
  temperature: number,
  maxOutputTokens: number,
  opts?: CallGeminiTextOptions
): Promise<string> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
  const body: Record<string, unknown> = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      temperature,
      maxOutputTokens,
    },
  };

  const genConfig = body.generationConfig as Record<string, unknown>;
  if (opts?.responseMimeType) genConfig.responseMimeType = opts.responseMimeType;
  if (opts?.responseSchema) genConfig.responseSchema = opts.responseSchema;

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Gemini error: ${res.status} ${t}`);
  }

  const data = (await res.json()) as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  return String(text);
}

/**
 * lineStopper: 用途 + 入力だけ受け取り、サーバでレート制限・Gemini 呼び出し・JSON 返却。
 * GEMINI_API_KEY は Firebase の環境変数で設定すること。
 */
export const lineStopper = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = assertAuthed(request);

    const inputText = clampText(request.data?.text, MAX_CHARS.lineStopper);
    if (!inputText) {
      throw new HttpsError("invalid-argument", "text required");
    }

    await lineStopperRateLimit(uid);

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      logger.error("GEMINI_API_KEY not set. Set in Firebase/Cloud Functions env. Returning fallback.");
      return safeFallbackLineStopper(inputText);
    }

    try {
      const prompt = buildLineStopperPrompt(inputText);
      const raw = await callGeminiText(prompt, apiKey, 0.2, MAX_OUTPUT_TOKENS.lineStopper);
      const jsonStr = extractBraceBlock(raw) ?? raw.trim();

      let obj: unknown;
      try {
        obj = JSON.parse(jsonStr);
      } catch {
        return safeFallbackLineStopper(inputText);
      }

      return sanitizeAndForceLineStopper(obj);
    } catch (e) {
      logger.warn("lineStopper Gemini or parse error", e);
      return safeFallbackLineStopper(inputText);
    }
  }
);

/**
 * lineStopperWorker: Cloud Tasks から呼ばれる HTTP。Gemini 実行 → jobs/{jobId} に結果保存。
 * 環境変数: GEMINI_API_KEY, WORKER_URL（Tasks 設定用）, TASKS_OIDC_SERVICE_ACCOUNT
 */
export const lineStopperWorker = onRequest(
  { region: "asia-northeast1" },
  async (req, res) => {
    try {
      const payloadB64 = req.body?.payload;
      if (!payloadB64) {
        res.status(400).send("missing payload");
        return;
      }
      const decoded = JSON.parse(
        Buffer.from(payloadB64, "base64").toString("utf8")
      ) as { jobId: string; uid: string; plan: string; text: string };

      const { jobId, uid, text: rawText } = decoded;
      if (!jobId || !uid || !rawText) {
        res.status(400).send("bad job");
        return;
      }
      const text = clampText(rawText, MAX_CHARS.lineStopper);

      const jobRef = db.collection("jobs").doc(jobId);
      const jobSnap = await jobRef.get();
      const queueTier = jobSnap.exists ? (jobSnap.data()?.queueTier ?? "standard") : "standard";
      logger.info("lineStopperWorker start", { jobId, uid, plan: decoded.plan, queueTier });

      const startMs = Date.now();
      await jobRef.set(
        {
          status: "RUNNING",
          startedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      let result: LineStopperResponse = safeFallbackLineStopper("");
      const apiKey = process.env.GEMINI_API_KEY;
      if (apiKey) {
        try {
          const prompt = buildLineStopperPrompt(text);
          const raw = await callGeminiText(prompt, apiKey, 0.2, MAX_OUTPUT_TOKENS.lineStopper);
          const jsonStr = extractBraceBlock(raw) ?? raw.trim();
          const obj = JSON.parse(jsonStr) as unknown;
          result = sanitizeAndForceLineStopper(obj);
        } catch (e) {
          logger.error("lineStopperWorker Gemini/parse failed", e);
        }
      } else {
        logger.error("GEMINI_API_KEY not set in worker");
      }

      await jobRef.set(
        {
          status: "DONE",
          finishedAt: FieldValue.serverTimestamp(),
          result: { ...result, queueTier },
        },
        { merge: true }
      );

      const plan = (decoded as { plan?: string }).plan ?? "free";
      const latencyMs = Math.round(Date.now() - startMs);
      const lineCheckRef = db.collection("users").doc(uid).collection("lineChecks").doc(jobId);
      await lineCheckRef.set(
        {
          createdAt: FieldValue.serverTimestamp(),
          risk: result.risk,
          oneLiner: result.oneLiner ?? "",
          suggestions: result.suggestions ?? [],
          planAtTime: plan,
          latencyMs,
          queue: {
            tier: plan === "subscription_yearly" ? "priority" : "standard",
            waitedMs: null,
          },
        },
        { merge: true }
      );

      res.status(200).send("ok");
    } catch (e) {
      logger.error("lineStopperWorker failed", e);
      res.status(500).send("error");
    }
  }
);

// --- aiWorker: lineStopper / rewrite / empathy の共通 HTTP Worker ---

function buildEmpathyPrompt(text: string): string {
  return `
あなたは、しんどい人に寄り添う日本語のカウンセラーです。

ユーザーの文章：
「${text}」

以下の2つを日本語で返してください。

1) 共感メッセージ：
   ユーザーを否定せず、「がんばりを認める」やさしい言葉。

2) 次の一歩：
   今日できそうな、ハードルの低い一歩。
   例：深呼吸を3回する／温かい飲み物を飲む など。
`.trim();
}

function parseEmpathyResponse(raw: string): { text: string; nextStep: string } {
  const trimmed = raw.trim();
  const match = trimmed.match(/(?:2[)）.]|②)\s*/);
  if (match && match.index != null && match.index > 0) {
    const empathy = trimmed.slice(0, match.index).replace(/^[\s\*]*(?:1[)）.]|①)[\s]*/i, "").trim();
    const nextStep = trimmed.slice(match.index + match[0].length).replace(/^[\s\*]*(?:次の一歩[：:]?)[\s]*/i, "").trim();
    return {
      text: empathy || trimmed,
      nextStep: nextStep || "今日はゆっくり休むだけで十分です。",
    };
  }
  return {
    text: trimmed,
    nextStep: "今日はゆっくり休むだけで十分です。",
  };
}

type AiWorkerPayload = {
  jobId: string;
  uid: string;
  plan: string;
  op?: "lineStopper" | "rewrite" | "empathy";
  text: string;
  context?: Record<string, unknown>;
};

export const aiWorker = onRequest(
  { region: "asia-northeast1" },
  async (req, res) => {
    try {
      const payloadB64 = req.body?.payload;
      if (!payloadB64) {
        res.status(400).send("missing payload");
        return;
      }
      const decoded = JSON.parse(
        Buffer.from(payloadB64, "base64").toString("utf8")
      ) as AiWorkerPayload;

      const { jobId, uid, text } = decoded;
      if (!jobId || !uid || !text) {
        res.status(400).send("bad job");
        return;
      }

      const op = decoded.op ?? "lineStopper";
      const jobRef = db.collection("jobs").doc(jobId);
      const jobSnap = await jobRef.get();
      const queueTier = jobSnap.exists ? (jobSnap.data()?.queueTier ?? "standard") : "standard";
      logger.info("aiWorker start", { jobId, uid, op, plan: decoded.plan, queueTier });

      const startMs = Date.now();
      await jobRef.set(
        {
          status: "RUNNING",
          startedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      const apiKey = process.env.GEMINI_API_KEY;
      const plan = decoded.plan ?? "free";

      if (op === "lineStopper") {
        const maxChars = getMaxCharsLineStopper(plan as Plan);
        const clampedText = clampText(text, maxChars);
        const maxOutputTokens = getMaxOutputTokensLineStopper(plan as Plan);
        let result: LineStopperResponse = safeFallbackLineStopper("");
        if (apiKey) {
          try {
            const prompt = buildLineStopperPrompt(clampedText);
            const raw = await callGeminiText(prompt, apiKey, 0.2, maxOutputTokens);
            const jsonStr = extractBraceBlock(raw) ?? raw.trim();
            const obj = JSON.parse(jsonStr) as unknown;
            result = sanitizeAndForceLineStopper(obj);
          } catch (e) {
            logger.error("aiWorker lineStopper failed", e);
          }
        }
        await jobRef.set(
          {
            status: "DONE",
            finishedAt: FieldValue.serverTimestamp(),
            result,
          },
          { merge: true }
        );
        const latencyMs = Math.round(Date.now() - startMs);
        const lineCheckRef = db.collection("users").doc(uid).collection("lineChecks").doc(jobId);
        await lineCheckRef.set(
          {
            createdAt: FieldValue.serverTimestamp(),
            risk: result.risk,
            oneLiner: result.oneLiner ?? "",
            suggestions: result.suggestions ?? [],
            planAtTime: plan,
            latencyMs,
            queue: {
              tier: plan === "subscription_yearly" ? "priority" : "standard",
              waitedMs: null,
            },
          },
          { merge: true }
        );
      } else if (op === "rewrite") {
        const rewriteStartMs = Date.now();
        const maxCharsReformulate = getMaxCharsReformulate(plan as Plan);
        const clampedText = clampText(text, maxCharsReformulate);
        logger.info("reformulate", { inputLength: clampedText.length });
        const ctx = decoded.context ?? {};
        const scene = String(ctx.scene ?? "仕事");
        const purpose = String(ctx.purpose ?? "気持ちを伝えたい");
        const audience = String(ctx.audience ?? "同僚");
        const tone = String(ctx.tone ?? "柔らかい");
        const isYearly = ctx.isYearly === true;

        let resultText = clampedText;
        let rewriteFallback: ReformulateLogPayload["fallback"] = "none";
        const maxOutputTokensReformulate = getMaxOutputTokensReformulate(plan as Plan);
        if (apiKey) {
          try {
            const prompt = buildReformulatePromptV2({
              scene,
              purpose,
              audience,
              tone,
              text: clampedText,
              isYearly,
            });
            const raw = await callGeminiText(prompt, apiKey, 0.15, maxOutputTokensReformulate, {
              responseMimeType: "application/json",
              responseSchema: REFORMULATE_SCHEMA,
            });
            const jsonStr = extractBraceBlock(raw) ?? raw.trim();
            const repaired = repairJSONString(jsonStr);
            try {
              const obj = JSON.parse(repaired) as ReformulateJson;
              const rewritten =
                typeof obj?.rewritten === "string" ? obj.rewritten.trim() : "";

              if (rewritten) {
                if (rewritten.length < 5) {
                  logger.warn("rewrite too short", {
                    rewritten,
                    rawPreview: raw?.slice?.(0, 200),
                  });
                  resultText = clampedText;
                  rewriteFallback = "empty_rewrite";
                } else {
                  resultText = stripWrappingQuotes(rewritten);
                }
              } else {
                logger.warn("rewrite JSON parsed but empty rewritten", {
                  rawPreview: raw?.slice?.(0, 200),
                });
                resultText = clampedText;
                rewriteFallback = "empty_rewrite";
              }
            } catch {
              resultText =
                sanitizeReformulateResponse(raw) || clampedText;
              rewriteFallback = "parse_fail";
            }
          } catch (e) {
            logger.error("aiWorker rewrite failed", e);
            rewriteFallback = "gemini_error";
          }
        }
        const rewriteLatencyMs = Math.round(Date.now() - rewriteStartMs);
        logReformulate({
          source: "job",
          op: "reformulate",
          tier: queueTier,
          plan,
          fallback: rewriteFallback,
          latencyMs: rewriteLatencyMs,
          inputLength: clampedText.length,
          outputLength: resultText.length,
          jobId,
        });
        await jobRef.set(
          {
            status: "DONE",
            finishedAt: FieldValue.serverTimestamp(),
            result: { text: resultText, source: "job" },
          },
          { merge: true }
        );
      } else if (op === "empathy") {
        const clampedText = clampText(text, MAX_CHARS.empathy);
        let resultEmpathy = { text: clampedText, nextStep: "今日はゆっくり休むだけで十分です。" };
        if (apiKey) {
          try {
            const prompt = buildEmpathyPrompt(clampedText);
            const raw = await callGeminiText(prompt, apiKey, 0.3, MAX_OUTPUT_TOKENS.empathy);
            resultEmpathy = parseEmpathyResponse(raw);
          } catch (e) {
            logger.error("aiWorker empathy failed", e);
          }
        }
        await jobRef.set(
          {
            status: "DONE",
            finishedAt: FieldValue.serverTimestamp(),
            result: { text: resultEmpathy.text, nextStep: resultEmpathy.nextStep },
          },
          { merge: true }
        );
      } else {
        await jobRef.set(
          { status: "FAILED", error: "UNKNOWN_OP" },
          { merge: true }
        );
      }

      res.status(200).send("ok");
    } catch (e) {
      logger.error("aiWorker failed", e);
      res.status(500).send("error");
    }
  }
);

// --- 言い換え: Functions で Gemini を叩く（キーはサーバのみ・JSON 固定で精度安定） ---

type ReformulateParams = {
  scene: string;
  purpose: string;
  audience: string;
  tone: string;
  text: string;
  isYearly: boolean;
};

const REFORMULATE_SCHEMA = {
  type: "object",
  properties: {
    critique: { type: "string" },
    risks: { type: "array", items: { type: "string" } },
    rewritten: { type: "string" },
  },
  required: ["critique", "risks", "rewritten"],
} as const;

type ReformulateJson = {
  rewritten?: unknown;
  critique?: unknown;
  risks?: unknown;
};

function looksLikeJsonObject(s: string): boolean {
  const t = s.trim();
  return t.startsWith("{") && t.endsWith("}");
}

function stripWrappingQuotes(s: string): string {
  let t = s.trim();
  if (
    (t.startsWith('"') && t.endsWith('"')) ||
    (t.startsWith("「") && t.endsWith("」"))
  ) {
    t = t.slice(1, -1).trim();
  }
  return t;
}

function repairJSONString(s: string): string {
  let t = s.trim();
  const fence = /^```(?:json)?\s*\n?/i;
  if (fence.test(t)) t = t.replace(fence, "").trim();
  if (t.endsWith("```")) t = t.slice(0, -3).trim();
  return t;
}

// --- 言い換えログ（経路・tier・fallback を同一フォーマットで観測用） ---
type ReformulateLogPayload = {
  source: "onCall" | "job";
  op: "reformulate";
  tier: "priority" | "standard";
  plan: string;
  used?: number;
  limit?: number;
  remaining?: number;
  fallback: "none" | "parse_fail" | "gemini_error" | "empty_rewrite" | "timeout";
  didRetry?: boolean;
  latencyMs: number;
  inputLength: number;
  outputLength: number;
  jobId?: string;
};

function logReformulate(payload: ReformulateLogPayload): void {
  logger.info("reformulate.end", payload);
}

function buildReformulatePromptV2(p: ReformulateParams): string {
  const scene = (p.scene ?? "").trim() || "不明";
  const purpose = (p.purpose ?? "").trim() || "不明";
  const audience = (p.audience ?? "").trim() || "不明";
  const tone = (p.tone ?? "").trim() || "不明";
  const text = (p.text ?? "").trim();

  const yearlyExtra = p.isYearly
    ? `- 年額ユーザー向け追加方針: 相手の立場/文脈を丁寧に汲み取り、"一度で伝わる"言い回しを選ぶ（ただし長文化しない）`
    : `- 追加方針: 端的に、誤解を減らす`;

  return `
あなたは「送信前メッセージ編集者」です。
ユーザーの本音は尊重しつつ、相手に伝わる形に"整える"のが仕事です。
お世辞や慰めは不要。率直に、前提を疑い、盲点を指摘してください。
ただし攻撃・人格批判・説教・決めつけは禁止。事実と推測を分け、冷静に。

【文脈】
- シーン: ${scene}
- 目的: ${purpose}
- 相手: ${audience}
- トーン: ${tone}
${yearlyExtra}

【入力文】
${text}

【作業手順】
rewritten は critique の思想をそのまま繰り返さない。critique は分析。rewritten は実務用。
1) critique: 相手が受け取る印象/盲点を率直に指摘（120文字以内）
2) risks: 誤解・関係悪化のリスクを最大3つ（短い箇条書き文）
3) rewritten: "そのまま送れる本文"を作成（最大6文、改行OK）
   - 余計な前置きや講釈は書かない
   - 詰問・断定・皮肉・脅しは禁止
   - 相手に逃げ道を1つ入れる（例: 時間あるときでOK）

【最重要：出力形式】
JSONのみ。説明・前置き・コードフェンス禁止。
キーは critique, risks, rewritten のみ。
`.trim();
}

/**
 * Reformulate の出力を安全に本文化。JSON なら rewritten を採用、否則は従来の prefix 削り（後方互換）。
 */
function sanitizeReformulateResponse(raw: string): string {
  const trimmed = (raw ?? "").trim();
  if (!trimmed) return "";

  const candidate =
    extractBraceBlock(trimmed) ??
    (trimmed.includes("{") && trimmed.includes("}") ? trimmed : null);

  if (candidate) {
    const maybeJson = repairJSONString(candidate);
    if (looksLikeJsonObject(maybeJson)) {
      try {
        const obj = JSON.parse(maybeJson) as ReformulateJson;
        const rewritten =
          typeof obj.rewritten === "string" ? obj.rewritten.trim() : "";
        if (rewritten) return stripWrappingQuotes(rewritten);
      } catch {
        // JSON として壊れている場合は後方互換へ
      }
    }
  }

  const prefixes = [
    "整形した文章：",
    "整形した文章:",
    "言い換え：",
    "言い換え:",
    "回答：",
    "回答:",
  ];
  let out = trimmed;
  for (const p of prefixes) {
    if (out.startsWith(p)) {
      out = out.slice(p.length).trim();
      break;
    }
  }
  out = stripWrappingQuotes(out);
  const final = out.trim();
  // 生 JSON の断片を返さない（"{" 等で出力が壊れるのを防ぐ。呼び出し元で fallbackText || text により入力文にフォールバック）
  if (final.startsWith("{") || (final.length <= 3 && final.includes("{"))) return "";
  return final;
}

/**
 * reformulate: 言い換え。text + scene/purpose/audience/tone を受け取り、サーバで Gemini 呼び出し。
 * 冒頭で本番レート制御（quota/{uid} 分・日）を実施。GEMINI_API_KEY は Firebase の環境変数で設定すること。
 */
export const reformulate = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = assertAuthed(request);
    const { plan, effectiveUntil } = await getCurrentPlan(uid);
    let actualPlan: Plan = plan;
    if (plan === "subscription_monthly" || plan === "subscription_yearly") {
      if (effectiveUntil == null || effectiveUntil === 0 || effectiveUntil < Date.now()) {
        actualPlan = "free";
      }
    }
    await assertFreeTrialOrPaid(uid, actualPlan);

    const maxChars = getMaxCharsReformulate(actualPlan);
    const text = clampText(request.data?.text, maxChars);
    logger.info("reformulate.entry", { uid: uid.slice(0, 8), textLength: text?.length ?? 0 });
    if (!text) {
      throw new HttpsError("invalid-argument", "text required");
    }

    const limits = await consumeAiLimits(uid, actualPlan, "reformulate");
    if (!limits.allowed) {
      throw new HttpsError("resource-exhausted", limits.reason ?? "resource-exhausted", limits);
    }

    const scene = String(request.data?.scene ?? "仕事");
    const purpose = String(request.data?.purpose ?? "気持ちを伝えたい");
    const audience = String(request.data?.audience ?? "同僚");
    const tone = String(request.data?.tone ?? "柔らかい");
    const isYearly = request.data?.isYearly === true;

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      logger.error("GEMINI_API_KEY not set. Set in Firebase/Cloud Functions env.");
      throw new HttpsError("failed-precondition", "API key not configured on server.");
    }

    logger.info("reformulate", { inputLength: text.length });
    const startMs = Date.now();
    try {
      const prompt = buildReformulatePromptV2({
        scene,
        purpose,
        audience,
        tone,
        text,
        isYearly,
      });
      const maxOutputTokens = getMaxOutputTokensReformulate(actualPlan);
      const raw = await callGeminiText(prompt, apiKey, 0.15, maxOutputTokens, {
        responseMimeType: "application/json",
        responseSchema: REFORMULATE_SCHEMA,
      });

      const jsonStr = extractBraceBlock(raw) ?? raw.trim();
      const repaired = repairJSONString(jsonStr);

      let obj: ReformulateJson & {
        rewritten?: string;
        critique?: string;
        risks?: string[];
      };
      try {
        obj = JSON.parse(repaired) as typeof obj;
      } catch {
        const fallbackText = sanitizeReformulateResponse(raw);
        const outText = fallbackText || text;
        logReformulate({
          source: "onCall",
          op: "reformulate",
          tier: limits.tier,
          plan: actualPlan,
          used: limits.daily?.used,
          limit: limits.daily?.limit,
          remaining: limits.daily?.remaining,
          fallback: "parse_fail",
          latencyMs: Math.round(Date.now() - startMs),
          inputLength: text.length,
          outputLength: outText.length,
        });
        return {
          text: outText,
          meta: { critique: "", risks: [], source: "onCall" },
          queueTier: limits.tier,
          limits,
        };
      }

      const rewritten =
        typeof obj?.rewritten === "string" ? obj.rewritten.trim() : "";
      const critique =
        typeof obj?.critique === "string" ? obj.critique.trim() : "";
      const risks = Array.isArray(obj?.risks)
        ? (obj.risks as unknown[])
            .filter((x): x is string => typeof x === "string")
            .slice(0, 3)
        : [];

      let safeText: string;
      let fallback: ReformulateLogPayload["fallback"] = "none";
      if (rewritten) {
        if (rewritten.length < 5) {
          logger.warn("reformulate rewritten too short", {
            rewritten,
            rawPreview: raw?.slice?.(0, 200),
          });
          safeText = text;
          fallback = "empty_rewrite";
        } else {
          safeText = stripWrappingQuotes(rewritten);
        }
      } else {
        logger.warn("reformulate JSON parsed but empty rewritten", {
          rawPreview: raw?.slice?.(0, 200),
        });
        safeText = text;
        fallback = "empty_rewrite";
      }

      logReformulate({
        source: "onCall",
        op: "reformulate",
        tier: limits.tier,
        plan: actualPlan,
        used: limits.daily?.used,
        limit: limits.daily?.limit,
        remaining: limits.daily?.remaining,
        fallback,
        latencyMs: Math.round(Date.now() - startMs),
        inputLength: text.length,
        outputLength: safeText.length,
      });

      return {
        text: safeText,
        meta: { critique, risks, source: "onCall" },
        queueTier: limits.tier,
        limits,
      };
    } catch (e) {
      logger.warn("reformulate Gemini error", e);
      logReformulate({
        source: "onCall",
        op: "reformulate",
        tier: limits.tier,
        plan: actualPlan,
        used: limits.daily?.used,
        limit: limits.daily?.limit,
        remaining: limits.daily?.remaining,
        fallback: "gemini_error",
        latencyMs: Math.round(Date.now() - startMs),
        inputLength: text.length,
        outputLength: text.length,
      });
      return { text: text, queueTier: limits.tier, limits, fallback: true };
    }
  }
);
