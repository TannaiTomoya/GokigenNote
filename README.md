# GokigenNote — LINE送信前チェック

既読無視で不安になって、  
強いLINEを送って後悔したことはありませんか？

---

## このアプリについて

このアプリは、  
**「感情のまま送ってしまうLINE」を送る前に整えるためのツール**です。

---

## 課題の明確化

不安なとき、人はこうなります：

- **既読無視** → 焦って追いLINE
- **寂しさ** → 重い文章になる
- **不安** → 強い言い方になる

その結果、関係を悪くしてしまう。

👉 **問題は「感情」ではなく、伝え方です。**

---

## コア機能：LINE送信前チェック

- 送る前の文章を**貼るだけ**
- **危険度を判定**（LOW / MEDIUM / HIGH）
- そのまま使える**改善案を3つ**提示

👉 「送る前に1回止める」だけで、関係が変わる

---

## 価値（ベネフィット）

- 感情を否定しない
- でも、**伝え方だけ整える**
- 相手に伝わる形に変える

👉 **「後悔しないLINE」を作る**

---

## ターゲット（1点に絞る）

- 既読無視で不安になりやすい人
- つい追いLINEしてしまう人
- 本当は優しくしたいのに、強くなってしまう人

---

## 締め

送ってから後悔する前に。  
**一度、立ち止まるためのアプリです。**

---

## 技術構成

- iOS: Swift / SwiftUI
- Backend: Firebase (Functions / Firestore)
- In-App Purchase: StoreKit 2
- AI: Gemini API
- LINE送信前チェック: `QuotaService.consumeRewrite` → Gemini（`<OUTPUT>` タグ・JSON）→ `extractJSON`（タグ/フェンス/brace）→ `repairJSONString` / `sanitizeLineStopperJSON` → decode

---

## 課金モデル

- 月額 / 年額サブスクリプション
- 買い切り（Lifetime）

※ 課金状態は Firestore の `entitlements` で管理

---

## セットアップ

```bash
git clone <repo>
cd GokigenNote-1
open GokigenNote.xcodeproj
```

- Firebase の `GoogleService-Info.plist` を配置
- Gemini API キーを `Gemini-Info.plist` または環境変数で設定（詳細は `SETUP.md` 参照）
