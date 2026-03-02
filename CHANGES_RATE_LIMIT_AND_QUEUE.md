# 変更箇所一覧（レート制限・Cloud Tasks 優先キュー）

## 新規追加

| ファイル | 内容 |
|----------|------|
| `functions/src/rateLimit.ts` | Firestore `rate_limits/{uid}` で 1分・1日カウント。POLICY: free 4/10, monthly 20/300, yearly 30/500, lifetime 20/300。`consumeRateLimit(uid, plan)` |
| `functions/src/tasks.ts` | Cloud Tasks 投入。`planToTier(plan)` → high/normal/low。`enqueueLineStopperJob({ jobId, uid, plan, text })` |

## 変更

### functions/package.json
- 依存追加: `@google-cloud/tasks`: `^5.0.0`

### functions/src/index.ts
- **import**: `onRequest`, `./rateLimit`（consumeRateLimit, RateLimitPlan）, `./tasks`（enqueueLineStopperJob）
- **resolvePlanForRateLimit(uid)**: `users/{uid}/entitlements/current` から `free`|`monthly`|`yearly`|`lifetime` を返す
- **consumeRewrite**: サブスク（monthly/yearly）時は「無制限 return」を廃止し、`consumeRateLimit(uid, monthly|yearly)` を実行。超過時は `allowed: false`, `reason: RPM_LIMIT|RPD_LIMIT`
- **enqueueLineStopper** (Callable): 認証 → text 検証 → resolvePlanForRateLimit → consumeRateLimit → `jobs/{jobId}` 作成 → enqueueLineStopperJob → `{ jobId, status: "QUEUED" }` を返す
- **getJobResult** (Callable): 認証 → `jobs/{jobId}` 取得 → uid 一致確認 → `{ status, result, error }` を返す
- **lineStopperWorker** (onRequest): POST body `{ payload: base64 }` → jobId/uid/text 取得 → ジョブ RUNNING → Gemini 実行 → ジョブ DONE + result 保存

### Services/LineStopperRemoteService.swift
- **旧**: Callable `lineStopper` を 1 回呼んで同期的に結果取得
- **新**: Callable `enqueueLineStopper(text)` で jobId 取得 → `getJobResult(jobId)` を 0.5 秒間隔で最大 12 秒ポーリング → status が DONE で result をパースして返却。FAILED / タイムアウト時はエラー

## デプロイ前に必要な作業

1. **Cloud Tasks キュー作成・更新**（asia-northeast1）  
   - キュー名: `ai-standard`, `ai-priority`（コードのデフォルト）  
   - **差を効かせる設定**（同じ設定だと「名前だけ優先」で意味なし）:  
     → **`functions/CLOUD_TASKS_QUEUES.md`** に推奨値と gcloud コマンドを記載。そのまま実行可能。
2. **環境変数**（Firebase Functions）  
   - `GEMINI_API_KEY`（既存）  
   - `WORKER_URL`: Worker の HTTPS URL（デプロイ後に取得）  
   - `TASKS_QUEUE_STANDARD`, `TASKS_QUEUE_PRIORITY`: 未設定時は `ai-standard`, `ai-priority`  
   - `CLOUD_TASKS_LOCATION`: 例 `asia-northeast1`  
   - `TASKS_OIDC_SERVICE_ACCOUNT`: Tasks が Worker を呼ぶためのサービスアカウントメール

## Firestore コレクション

- **rate_limits/{uid}**: minuteKey, minuteCount, dayKey, dayCount, lastSeenAt（トランザクションで更新）
- **jobs/{jobId}**: uid, plan, status (QUEUED|RUNNING|DONE|FAILED), textPreview, result, error, taskName, createdAt, startedAt, finishedAt
