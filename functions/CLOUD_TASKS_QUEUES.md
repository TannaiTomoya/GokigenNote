# Cloud Tasks キュー設定（priority / standard の差を効かせる）

**重要**: 両キューを同じ設定のままにすると「名前だけ優先」で実質同じ速度になる。  
年額ユーザーに「速さ＝価値」を感じさせるには、以下の差をつける。

---

## 推奨設定（コピペ用）

| 項目 | ai-standard | ai-priority |
|------|-------------|-------------|
| maxDispatchesPerSecond | 2 | 10 |
| maxConcurrentDispatches | 2 | 10 |
| retryConfig.maxAttempts | 3 | 5 |
| retryConfig.maxRetryDuration | 300s | 120s |
| backoff（min/max） | 5s / 60s | 1s / 10s |

**意味**
- **priority** → すぐ処理・詰まらない
- **standard** → 混雑時に意図的に遅れる → 課金理由になる

---

## gcloud コマンド（そのまま実行）

リージョンは `asia-northeast1`。プロジェクトは `gcloud config get-value project` で確認。

### standard（遅めに制限）

```bash
gcloud tasks queues update ai-standard \
  --location=asia-northeast1 \
  --max-dispatches-per-second=2 \
  --max-concurrent-dispatches=2 \
  --max-attempts=3 \
  --min-backoff=5s \
  --max-backoff=60s
```

### priority（速くする）

```bash
gcloud tasks queues update ai-priority \
  --location=asia-northeast1 \
  --max-dispatches-per-second=10 \
  --max-concurrent-dispatches=10 \
  --max-attempts=5 \
  --min-backoff=1s \
  --max-backoff=10s
```

---

## 見落としがちなポイント

1. **両方同じ設定 → 差が出ない**  
   上記の数値差を必ず入れる。

2. **Worker が詰まると priority でも遅い**  
   - Cloud Functions / Cloud Run の **max instances** と **concurrency** を確認。
   - 推奨: `concurrency` 10〜20、`max instances` 5 以上。

3. **Gemini API の RPM 制限**  
   プロジェクト全体の RPM 制限に達すると、priority キューだけ速くしても詰まる。  
   差を体感させるには Worker と Gemini の余裕も必要。

---

## 期待される UX

| プラン | 体感 |
|--------|------|
| 年額（priority） | ほぼ即レス（1〜2秒） |
| 無料・月額（standard） | 混雑時 3〜8秒、worst 10秒以上 |

→ 「感情が高ぶった瞬間に差を感じる」＝課金理由になる。

---

## 確認手順

1. 上記 gcloud でキュー更新（約 5 分）
2. 実機で **無料で連打** → 遅くなるか確認
3. **年額**で同じ操作 → 明確に速いか確認
4. 差が出ない場合 → Worker の concurrency / max instances または Gemini 制限がボトルネック
