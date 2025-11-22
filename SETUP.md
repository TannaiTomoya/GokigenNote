# セットアップガイド

## 🚀 クイックスタート

### 1. プロジェクトをクローン

```bash
git clone <repository-url>
cd GokigenNote
```

### 2. Xcodeでプロジェクトを開く

```bash
open GokigenNote.xcodeproj
```

### 3. ビルド＆実行

1. **デバイスまたはシミュレーターを選択**
2. **⌘R を押す** または **Product → Run**
3. アプリが起動します！

> **注意**: 初回ビルド時、Swift Package Manager が `GoogleGenerativeAI` パッケージを自動的にダウンロードします。

---

## 🔧 Gemini API の設定（オプション）

アプリは Gemini API なしでも動作しますが、より高度な言い換え機能を使いたい場合は以下の手順で設定してください。

### 手順

#### 1. Google AI Studio でAPIキーを取得

[Google AI Studio](https://makersuite.google.com/app/apikey) にアクセスして、無料のAPIキーを取得します。

#### 2. APIキーを設定（2つの方法）

##### 方法A: 環境変数で設定（推奨）

**Xcodeのスキーム設定から環境変数を追加：**

1. Xcode で `Product` → `Scheme` → `Edit Scheme...` を選択
2. 左側のメニューから `Run` を選択
3. `Arguments` タブをクリック
4. `Environment Variables` セクションで `+` ボタンをクリック
5. 以下を追加：
   - **Name**: `GEMINI_API_KEY`
   - **Value**: 取得したAPIキー
6. `Close` をクリック

**または、ターミナルから起動：**

```bash
cd /Users/tannaitomoya/smift-camp/GokigenNote
export GEMINI_API_KEY="your-api-key-here"
open GokigenNote.xcodeproj
```

##### 方法B: plistファイルで設定

プロジェクトルートに `Gemini-Info.plist` ファイルを作成します：

```bash
cd /Users/tannaitomoya/smift-camp/GokigenNote
touch Gemini-Info.plist
```

`Gemini-Info.plist` を開いて、以下の内容をペーストします：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>API_KEY</key>
    <string>あなたのAPIキーをここに貼り付け</string>
</dict>
</plist>
```

> **⚠️ 重要**: 
> - APIキーの読み込み優先順位: 1. 環境変数 → 2. plistファイル
> - `Gemini-Info.plist` は `.gitignore` に含まれているため、Git にコミットされません
> - APIキーは絶対に公開リポジトリにプッシュしないでください

#### 3. ビルド＆実行

- **Clean Build**: ⌥⇧⌘K
- **Run**: ⌘R

これで Gemini API が有効になります！

---

## 🔍 動作確認

### ローカルモード（デフォルト）

1. アプリを起動
2. 気分を選択
3. テキストを入力
4. 「言い換えをつくる」をタップ
5. → ローカルの `EmpathyEngine` が動作します

### Gemini モード（API設定後）

1. 上記の手順でAPIキーを設定
2. アプリを再ビルド
3. 「言い換えをつくる」をタップ
4. → Gemini API が呼ばれ、より高度な言い換えが生成されます

---

## 🐛 トラブルシューティング

### ビルドエラー: "No such module 'GoogleGenerativeAI'"

**解決方法**:
1. Xcode でメニューから **File → Packages → Reset Package Caches**
2. **Product → Clean Build Folder** (⌥⇧⌘K)
3. 再ビルド (⌘B)

### アプリが起動時にクラッシュする

**解決方法**:
1. すべてのブレークポイントを無効化: **⌘Y**
2. DerivedData を削除:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/GokigenNote-*
   ```
3. Clean Build: ⌥⇧⌘K
4. 再ビルド: ⌘R

### "Gemini API key not found" 警告

これは**警告**であり、エラーではありません。アプリは正常に動作します（ローカルモード）。

Gemini API を使いたい場合は、上記の「Gemini API の設定」を参照してください。

---

## 📱 推奨テスト環境

- **iOS 18.0+**
- **実機**: iPhone 14 以降推奨
- **シミュレーター**: iPhone 15 Pro

---

## 🔒 セキュリティ

- **APIキーは絶対に公開しないでください**
- `Gemini-Info.plist` は `.gitignore` に含まれています
- ローカルデータは UserDefaults に保存（デバイス内のみ）

---

## 💡 ヒント

### Clean Build が必要なタイミング

- パッケージ依存関係を変更した後
- プロジェクト設定を変更した後
- 原因不明のビルドエラーが発生した時

### ブレークポイントを一括無効化

デバッグ中にブレークポイントで止まりすぎる場合：
- **⌘Y** で一括無効化/有効化を切り替え

### データをリセット

アプリのデータをリセットしたい場合：
1. アプリをアンインストール
2. または、シミュレーターで **Device → Erase All Content and Settings...**

---

## 📚 さらに詳しく

- [README.md](./README.md) - プロジェクト概要
- [Apple SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Google Gemini API Documentation](https://ai.google.dev/docs)

