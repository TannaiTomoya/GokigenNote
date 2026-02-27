# GokigenNote

感情のまま送って後悔する前に。  
「伝わる言葉」に変えるアプリ。

---

## 🎯 ターゲット

- LINEで感情をぶつけてしまい、後悔したことがある人
- 既読無視で不安になり、強い言葉を送ってしまう人
- 本当は優しくしたいのに、攻撃的になってしまう人

---

## 💡 解決する課題

多くの人は「感情」と「伝え方」を分けられていません。

- 不安 → 攻撃的な文章になる
- 寂しさ → 重いLINEになる
- 焦り → 相手を追い詰める

その結果、
関係を壊してしまう。

---

## 🚀 コア体験

1. **地雷LINEストッパー**（メイン）：送信予定のLINEを貼る → 危険度（LOW/MED/HIGH）と改善案3つを表示 → コピーして送信
2. 思ったことをそのまま入力（音声 / テキスト）
3. 感情と本音を可視化
4. 「伝わる言い方」に自動変換・送信前チェック

---

## ✨ 主な機能

### ⚠️ 地雷LINEストッパー（送信前チェック）
- タブの先頭に配置。LINE文を貼って「危険度をチェックする」で即判定
- 危険度＋一言説明（oneLiner）＋改善案3つ（柔らかく／余裕／距離）をAI生成
- 制限時はPaywall表示。QuotaService でサーバ側枠管理、Gemini で JSON 出力（`<OUTPUT>` タグ方式・brace 抽出・repair/sanitize で崩れに強い）

### 📝 感情の吐き出し
フィルターなしで、思ったまま入力できる

### 🧠 感情と言語化
「怒り」「不安」「寂しさ」などを可視化

### 💬 LINE言い換え
- 柔らかい / 素直 / 魅力的 の3パターンを提示

---

## 🧩 技術構成

- iOS: Swift / SwiftUI
- Backend: Firebase (Functions / Firestore)
- In-App Purchase: StoreKit 2
- AI: Gemini API
- 地雷LINEストッパー: `QuotaService.consumeRewrite` → Gemini（`<OUTPUT>` タグ・JSON）→ `extractJSON`（タグ/フェンス/brace）→ `repairJSONString` / `sanitizeLineStopperJSON` → decode

---

## 🔐 課金モデル

- 月額 / 年額サブスクリプション
- 買い切り（Lifetime）

※ 課金状態は Firestore の `entitlements` で管理

---

## 📌 なぜこのアプリを作るのか

人は「感情のままの言葉」で関係を壊します。

でも本当は、
傷つけたいわけじゃない。

このアプリは、
「本音はそのままに、伝え方だけを変える」ためのものです。

---

## 📈 今後の展開

- 会話履歴からの改善提案
- パートナーとの関係分析
- シーン別（恋愛 / 仕事 / 友人）の最適化

---

## 🛠 セットアップ

```bash
git clone <repo>
cd GokigenNote-1
open GokigenNote.xcodeproj
```

- Firebase の `GoogleService-Info.plist` を配置
- Gemini API キーを `Gemini-Info.plist` または環境変数で設定（詳細は `SETUP.md` 参照）
