# ごきげんノート

日々の気分を記録し、やさしい言葉で振り返ることができるメンタルケアアプリです。

## 📱 主な機能

### ✨ 気分の記録
- 5段階の気分選択（😊 🙂 😐 😞 😢）
- 自由なテキスト入力
- 気分に応じた例文挿入

### 💬 やさしい言い換え
- ローカルの感情分析エンジン（`EmpathyEngine`）
- Google Gemini API との連携（オプション）
- ユーザーを否定しない、前向きなフィードバック

### 📊 傾向分析
- 直近14件の記録から傾向を分析
- 平均スコア、ポジティブ/ネガティブ比率
- 連続記録日数のトラッキング

### 💾 データ管理
- ローカルストレージでのプライバシー保護
- JSON形式でのデータエクスポート
- ShareSheetによる簡単なバックアップ

## 🛠️ 技術スタック

- **フレームワーク**: SwiftUI
- **最小対応バージョン**: iOS 18.0+
- **アーキテクチャ**: MVVM
- **データ永続化**: UserDefaults + Codable
- **AI連携**: Google Gemini API (Optional)

## 📂 プロジェクト構造

```
GokigenNote/
├── Models/
│   ├── Entry.swift          # 日記エントリのデータモデル
│   ├── Mood.swift            # 気分の定義（5段階）
│   ├── PromptProvider.swift  # ランダムな問いの提供
│   └── TrendSnapshot.swift   # 傾向分析のデータ構造
├── Views/
│   ├── ContentView.swift     # メイン画面
│   ├── HistoryListView.swift # 履歴一覧
│   └── EntryDetailView.swift # 詳細表示
├── ViewModels/
│   └── GokigenViewModel.swift # ビジネスロジック
├── Services/
│   ├── Persistence.swift     # データ永続化
│   ├── EmpathyEngine.swift   # ローカル言い換えエンジン
│   ├── GeminiService.swift   # Gemini API連携
│   └── APIKey.swift          # API キー管理
└── GokigenNoteApp.swift/
    ├── GokigenNoteApp.swift  # アプリエントリーポイント
    └── Assets.xcassets/      # アセット
```

## 🔐 Gemini API の設定（オプション）

1. [Google AI Studio](https://aistudio.google.com/apikey) で API キーを取得（言い換え・共感メッセージに必要。未設定時はローカル処理のみ）

2. **方法1: 環境変数で設定（推奨）**

Xcodeのスキームに環境変数を追加：

- Xcode で `Product` → `Scheme` → `Edit Scheme...` を選択
- `Run` → `Arguments` → `Environment Variables` に以下を追加：
  - Name: `GEMINI_API_KEY`
  - Value: 取得したAPIキー

**または**

- `.xcodeproj` を右クリック → Show in Finder
- ターミナルで以下を実行：
```bash
cd /path/to/GokigenNote
export GEMINI_API_KEY="your-api-key-here"
open GokigenNote.xcodeproj
```

3. **方法2: plistファイルで設定**

`Gemini-Info.plist` を作成：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>API_KEY</key>
    <string>YOUR_GEMINI_API_KEY_HERE</string>
</dict>
</plist>
```

4. `.gitignore` にすでに追加済みなので、APIキーは安全です

> **注意**: APIキーが未設定でも、ローカルの `EmpathyEngine` で動作します。
> 
> APIキーの読み込み優先順位:
> 1. 環境変数 `GEMINI_API_KEY`
> 2. `Gemini-Info.plist` ファイル

## 🚀 ビルド＆実行

### 必要な環境
- Xcode 16.0+
- iOS 18.0+ デバイスまたはシミュレーター

### 手順

1. **リポジトリをクローン**
```bash
git clone <repository-url>
cd GokigenNote
```

2. **Xcodeでプロジェクトを開く**
```bash
open GokigenNote.xcodeproj
```

3. **Swift Package Manager の依存関係を解決**
   - Xcode が自動的に `GoogleGenerativeAI` パッケージをダウンロード

4. **ビルド＆実行**
   - ⌘R または Product → Run

## 📝 使い方

1. **気分を選択** - 今の気分に近い絵文字をタップ
2. **問いに答える** - 表示された問いに沿って、または自由に入力
3. **例文を参考に** - 必要に応じて「例文を挿入」ボタンで気分に応じた例文を挿入
4. **言い換えを確認** - 「言い換えをつくる」でやさしい表現に変換
5. **記録する** - 「この一言を記録する」で保存
6. **履歴を振り返る** - 「すべての記録を見る」から過去の記録を確認
7. **傾向を確認** - 最下部のトレンドカードで自分の傾向を把握

## 🎨 デザインコンセプト

- **ミニマル**: Apple標準デザインに準拠したクリーンなUI
- **やさしさ**: ユーザーを責めない、前向きなトーン
- **アクセシビリティ**: VoiceOver対応、Dynamic Type対応
- **ダークモード**: 完全対応

## 🔒 プライバシー

- ログイン後は記録データがFirestoreクラウドに保存されます
- 「言い換えをつくる」「共感メッセージ」等の利用時、入力テキストは **Google の AI（Gemini API）** に送信され、結果表示のためだけに利用されます（Google の[利用規約](https://ai.google.dev/terms)・[プライバシーポリシー](https://policies.google.com/privacy)に従います）
- エクスポート機能で自分でバックアップ可能

## 🤝 コントリビューション

このプロジェクトは個人開発です。フィードバックや改善案は歓迎します。

## 📄 ライセンス

このプロジェクトは教育目的で作成されました。

## 👤 作成者

丹内智弥 (Tomoya Tannai)

---

**⚠️ 重要**: このアプリはメンタルヘルスの専門的なサポートを提供するものではありません。深刻な悩みがある場合は、専門機関にご相談ください。

