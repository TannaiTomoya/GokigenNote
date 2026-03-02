/**
 * レート制御: 24h 合算キャップ + op別 RPM。quota/{uid} に dailyStartMs / dailyUsed / rpmBuckets。
 * resource-exhausted 時も成功時も同じ RateLimitDetails を返し、iOS が一枚のモーダルで処理できるようにする。
 */
import { getFirestore, FieldValue } from "firebase-admin/firestore";

export type RateLimitPlan = "free" | "monthly" | "yearly" | "lifetime";
export type Tier = "standard" | "priority";
export type AiOp = "lineStopper" | "reformulate" | "empathy";

let _db: ReturnType<typeof getFirestore> | null = null;
function getDb(): ReturnType<typeof getFirestore> {
  if (!_db) _db = getFirestore();
  return _db;
}

const DAILY_BUDGET_LIMITS: Record<RateLimitPlan, number> = {
  free: 10,
  monthly: 30,
  yearly: 30,
  lifetime: 60,
};

const RPM_LIMITS: Record<RateLimitPlan, Record<AiOp, number>> = {
  free: { lineStopper: 2, reformulate: 2, empathy: 2 },
  lifetime: { lineStopper: 6, reformulate: 6, empathy: 4 },
  monthly: { lineStopper: 8, reformulate: 8, empathy: 6 },
  yearly: { lineStopper: 12, reformulate: 10, empathy: 8 },
};

const DAY_WINDOW_MS = 24 * 60 * 60 * 1000;
const RPM_WINDOW_SECONDS = 60;
const RPM_WINDOW_MS = RPM_WINDOW_SECONDS * 1000;

export type RateLimitDetails = {
  allowed: boolean;
  plan: string;
  tier: Tier;
  op: AiOp;
  daily: {
    limit: number;
    used: number;
    remaining: number;
    resetAtMs: number;
  };
  rpm: {
    limit: number;
    windowSeconds: number;
    used: number;
    remaining: number;
    resetAtMs: number;
  };
  retryAfterSeconds?: number;
  reason?: "daily_budget_exceeded" | "rpm_exceeded" | "unknown";
};

export function tierForServerPlan(serverPlan: string): Tier {
  return serverPlan === "subscription_yearly" ? "priority" : "standard";
}

export function rateLimitPlanForServerPlan(serverPlan: string): RateLimitPlan {
  if (serverPlan === "subscription_yearly") return "yearly";
  if (serverPlan === "subscription_monthly") return "monthly";
  if (serverPlan === "lifetime") return "lifetime";
  return "free";
}

function nowMs(): number {
  return Date.now();
}

function calcRetryAfterSeconds(resetAtMs: number): number {
  const ms = Math.max(0, resetAtMs - nowMs());
  return Math.ceil(ms / 1000);
}

/**
 * quota/{uid}: dailyStartMs, dailyUsed（24h rolling）
 */
export async function consumeDailyBudget(
  uid: string,
  ratePlan: RateLimitPlan,
  serverPlanRaw: string,
  op: AiOp
): Promise<RateLimitDetails> {
  const tier = tierForServerPlan(serverPlanRaw);
  const dailyLimit = DAILY_BUDGET_LIMITS[ratePlan];
  const rpmLimit = RPM_LIMITS[ratePlan][op];
  const quotaRef = getDb().collection("quota").doc(uid);

  const result = await getDb().runTransaction(async (tx) => {
    const snap = await tx.get(quotaRef);
    const data = (snap.exists ? snap.data() : {}) as Record<string, unknown>;

    const now = nowMs();
    let dailyStartMs = typeof data.dailyStartMs === "number" ? data.dailyStartMs : 0;
    let dailyUsed = typeof data.dailyUsed === "number" ? data.dailyUsed : 0;

    if (!dailyStartMs || now - dailyStartMs >= DAY_WINDOW_MS) {
      dailyStartMs = now;
      dailyUsed = 0;
    }

    const resetAtMs = dailyStartMs + DAY_WINDOW_MS;
    const nextUsed = dailyUsed + 1;
    const allowed = nextUsed <= dailyLimit;

    if (allowed) {
      tx.set(
        quotaRef,
        {
          dailyStartMs,
          dailyUsed: nextUsed,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } else {
      tx.set(
        quotaRef,
        { dailyStartMs, dailyUsed, updatedAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
    }

    const used = allowed ? nextUsed : dailyUsed;
    const remaining = Math.max(0, dailyLimit - used);

    const details: RateLimitDetails = {
      allowed,
      plan: serverPlanRaw,
      tier,
      op,
      daily: { limit: dailyLimit, used, remaining, resetAtMs },
      rpm: {
        limit: rpmLimit,
        windowSeconds: RPM_WINDOW_SECONDS,
        used: 0,
        remaining: rpmLimit,
        resetAtMs: now + RPM_WINDOW_MS,
      },
      reason: allowed ? undefined : "daily_budget_exceeded",
      retryAfterSeconds: allowed ? undefined : calcRetryAfterSeconds(resetAtMs),
    };

    return details;
  });

  return result;
}

const bucketKey = (op: AiOp): string => `rpm:${op}`;

/**
 * quota/{uid}: rpmBuckets[`rpm:${op}`] = { startMs, used }
 */
export async function consumeRpm(
  uid: string,
  ratePlan: RateLimitPlan,
  serverPlanRaw: string,
  op: AiOp
): Promise<Pick<RateLimitDetails, "allowed" | "rpm" | "reason" | "retryAfterSeconds">> {
  const limit = RPM_LIMITS[ratePlan][op];
  const quotaRef = getDb().collection("quota").doc(uid);
  const key = bucketKey(op);

  const res = await getDb().runTransaction(async (tx) => {
    const snap = await tx.get(quotaRef);
    const data = (snap.exists ? snap.data() : {}) as Record<string, unknown>;
    const rpmBuckets = (data.rpmBuckets ?? {}) as Record<string, { startMs?: number; used?: number }>;
    const bucket = rpmBuckets[key] ?? {};

    const now = nowMs();
    let startMs = typeof bucket.startMs === "number" ? bucket.startMs : 0;
    let used = typeof bucket.used === "number" ? bucket.used : 0;

    if (!startMs || now - startMs >= RPM_WINDOW_MS) {
      startMs = now;
      used = 0;
    }

    const resetAtMs = startMs + RPM_WINDOW_MS;
    const nextUsed = used + 1;
    const allowed = nextUsed <= limit;

    rpmBuckets[key] = { startMs, used: allowed ? nextUsed : used };
    tx.set(
      quotaRef,
      { rpmBuckets, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );

    const currentUsed = allowed ? nextUsed : used;
    const remaining = Math.max(0, limit - currentUsed);

    return {
      allowed,
      rpm: {
        limit,
        windowSeconds: RPM_WINDOW_SECONDS,
        used: currentUsed,
        remaining,
        resetAtMs,
      },
      reason: allowed ? undefined : ("rpm_exceeded" as const),
      retryAfterSeconds: allowed ? undefined : calcRetryAfterSeconds(resetAtMs),
    };
  });

  return res;
}

/**
 * 24h合算 → RPM の順で判定。1トランザクション内で daily を先に判定・消費し、OK なら rpm を消費。
 * rpm で NG の場合も daily は1消費する（スクリプト連打を総量で抑えるため）。
 */
export async function consumeAiLimits(
  uid: string,
  serverPlanRaw: string,
  op: AiOp
): Promise<RateLimitDetails> {
  const ratePlan = rateLimitPlanForServerPlan(serverPlanRaw);
  const tier = tierForServerPlan(serverPlanRaw);
  const dailyLimit = DAILY_BUDGET_LIMITS[ratePlan];
  const rpmLimit = RPM_LIMITS[ratePlan][op];
  const quotaRef = getDb().collection("quota").doc(uid);
  const key = bucketKey(op);

  return getDb().runTransaction(async (tx) => {
    const snap = await tx.get(quotaRef);
    const data = (snap.exists ? snap.data() : {}) as Record<string, unknown>;

    const now = nowMs();
    let dailyStartMs =
      typeof data.dailyStartMs === "number" ? data.dailyStartMs : 0;
    let dailyUsed =
      typeof data.dailyUsed === "number" ? data.dailyUsed : 0;

    if (!dailyStartMs || now - dailyStartMs >= DAY_WINDOW_MS) {
      dailyStartMs = now;
      dailyUsed = 0;
    }

    const dailyResetAtMs = dailyStartMs + DAY_WINDOW_MS;

    // dailyは必ず1消費を試みる（rpmで落ちてもdailyは消費）
    const nextDailyUsed = dailyUsed + 1;
    const dailyAllowed = nextDailyUsed <= dailyLimit;

    // 消費後の値
    const usedDaily = dailyAllowed ? nextDailyUsed : dailyUsed;
    const dailyRemaining = Math.max(0, dailyLimit - usedDaily);

    const rpmBuckets = { ...((data.rpmBuckets as Record<string, { startMs?: number; used?: number }>) ?? {}) };
    const bucket = rpmBuckets[key] ?? {};
    let startMs = typeof bucket.startMs === "number" ? bucket.startMs : 0;
    let rpmUsed = typeof bucket.used === "number" ? bucket.used : 0;

    if (!startMs || now - startMs >= RPM_WINDOW_MS) {
      startMs = now;
      rpmUsed = 0;
    }

    const rpmResetAtMs = startMs + RPM_WINDOW_MS;
    const nextRpmUsed = rpmUsed + 1;
    const rpmAllowed = nextRpmUsed <= rpmLimit;

    if (rpmAllowed && dailyAllowed) {
      rpmUsed = nextRpmUsed;
    }

    rpmBuckets[key] = { startMs, used: rpmUsed };
    const updates: Record<string, unknown> = {
      dailyStartMs,
      dailyUsed: usedDaily,
      rpmBuckets,
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.set(quotaRef, updates, { merge: true });

    const rpmRemaining = Math.max(0, rpmLimit - rpmUsed);
    const allowed = dailyAllowed && rpmAllowed;

    return {
      allowed,
      plan: serverPlanRaw,
      tier,
      op,
      daily: {
        limit: dailyLimit,
        used: usedDaily,
        remaining: dailyRemaining,
        resetAtMs: dailyResetAtMs,
      },
      rpm: {
        limit: rpmLimit,
        windowSeconds: RPM_WINDOW_SECONDS,
        used: rpmUsed,
        remaining: rpmRemaining,
        resetAtMs: rpmResetAtMs,
      },
      reason: allowed ? undefined : (!dailyAllowed ? "daily_budget_exceeded" : "rpm_exceeded"),
      retryAfterSeconds: allowed
        ? undefined
        : calcRetryAfterSeconds(!dailyAllowed ? dailyResetAtMs : rpmResetAtMs),
    };
  });
}

/**
 * 読取のみ。消費せずに現在の daily/rpm 状態から RateLimitDetails を返す（consumeRewrite 用）。
 */
export async function getCurrentDetails(
  uid: string,
  serverPlanRaw: string,
  op: AiOp
): Promise<RateLimitDetails> {
  const ratePlan = rateLimitPlanForServerPlan(serverPlanRaw);
  const tier = tierForServerPlan(serverPlanRaw);
  const dailyLimit = DAILY_BUDGET_LIMITS[ratePlan];
  const rpmLimit = RPM_LIMITS[ratePlan][op];
  const quotaRef = getDb().collection("quota").doc(uid);
  const snap = await quotaRef.get();
  const data = (snap.exists ? snap.data() : {}) as Record<string, unknown>;

  const now = nowMs();
  let dailyStartMs =
    typeof data.dailyStartMs === "number" ? data.dailyStartMs : 0;
  let dailyUsed =
    typeof data.dailyUsed === "number" ? data.dailyUsed : 0;

  let dailyResetAtMs: number;

  if (!dailyStartMs) {
    // まだ一度も使っていない
    dailyResetAtMs = now + DAY_WINDOW_MS;
    dailyUsed = 0;
  } else if (now - dailyStartMs >= DAY_WINDOW_MS) {
    // 既に期限切れ → 次回consume時にリセット
    dailyResetAtMs = now + DAY_WINDOW_MS;
    dailyUsed = 0;
  } else {
    dailyResetAtMs = dailyStartMs + DAY_WINDOW_MS;
  }

  const dailyRemaining = Math.max(0, dailyLimit - dailyUsed);

  const rpmBuckets = (data.rpmBuckets ?? {}) as Record<string, { startMs?: number; used?: number }>;
  const bucket = rpmBuckets[bucketKey(op)] ?? {};
  let startMs = typeof bucket.startMs === "number" ? bucket.startMs : 0;
  let rpmUsed = typeof bucket.used === "number" ? bucket.used : 0;
  if (!startMs || now - startMs >= RPM_WINDOW_MS) {
    startMs = now;
    rpmUsed = 0;
  }
  const rpmResetAtMs = startMs + RPM_WINDOW_MS;
  const rpmRemaining = Math.max(0, rpmLimit - rpmUsed);

  const allowed = dailyUsed < dailyLimit && rpmUsed < rpmLimit;

  return {
    allowed,
    plan: serverPlanRaw,
    tier,
    op,
    daily: {
      limit: dailyLimit,
      used: dailyUsed,
      remaining: dailyRemaining,
      resetAtMs: dailyResetAtMs,
    },
    rpm: {
      limit: rpmLimit,
      windowSeconds: RPM_WINDOW_SECONDS,
      used: rpmUsed,
      remaining: rpmRemaining,
      resetAtMs: rpmResetAtMs,
    },
    retryAfterSeconds: allowed ? undefined : calcRetryAfterSeconds(dailyUsed >= dailyLimit ? dailyResetAtMs : rpmResetAtMs),
    reason: allowed ? undefined : (dailyUsed >= dailyLimit ? "daily_budget_exceeded" : "rpm_exceeded"),
  };
}
