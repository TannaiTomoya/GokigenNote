# Firebase ログイン機能のセットアップガイド

## 🔥 Firebase プロジェクトの設定

### 1. Firebase プロジェクトの作成

1. [Firebase Console](https://console.firebase.google.com/) にアクセス
2. 「プロジェクトを追加」をクリック
3. プロジェクト名を入力（例: GokigenNote）
4. Google Analytics は任意で設定

### 2. iOS アプリの追加

1. Firebase プロジェクトのダッシュボードで「iOS アプリを追加」を選択
2. バンドル ID を入力: `com.tomoya.tannnai.GokigenNote`
3. アプリのニックネームを入力（任意）
4. 「アプリを登録」をクリック

### 3. GoogleService-Info.plist のダウンロード

1. Firebase Console から `GoogleService-Info.plist` をダウンロード
2. Xcode プロジェクトのルート（`GokigenNote/` ディレクトリ）に追加
3. ⚠️ **重要**: `.gitignore` に既に追加済みなので、コミットされません

### 4. Firebase SDK の追加

Xcode で以下の手順を実行：

1. プロジェクトファイルを選択
2. `Package Dependencies` タブを選択
3. `+` ボタンをクリック
4. 以下のURLを入力:
   - `https://github.com/firebase/firebase-ios-sdk`
5. Version: `10.0.0` 以上を選択
6. 以下のプロダクトを追加:
   - ✅ FirebaseAuth
   - ✅ FirebaseFirestore
7. 同様に Google Sign-In SDK を追加:
   - `https://github.com/google/GoogleSignIn-iOS`
   - ✅ GoogleSignIn
   - ✅ GoogleSignInSwift

### 5. 認証方法の有効化

#### メールアドレス＋パスワード認証

1. Firebase Console → Authentication → Sign-in method
2. 「メール/パスワード」を選択
3. 「有効にする」をON
4. 保存

#### Google Sign-In の設定

1. Firebase Console → Authentication → Sign-in method
2. 「Google」を選択
3. 「有効にする」をON
4. プロジェクトのサポートメールを設定
5. 保存

### 6. Firestore Database の設定

1. Firebase Console → Firestore Database
2. 「データベースを作成」をクリック
3. 本番環境モードで開始（後でルールを設定）
4. ロケーションを選択: `asia-northeast1` (東京)
5. 「有効にする」をクリック

### 7. Firestore セキュリティルールの設定

Firebase Console → Firestore Database → ルール で以下を設定:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // ユーザーは自分のデータのみアクセス可能
    match /users/{userId}/entries/{entryId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

「公開」をクリックして保存。

### 8. Info.plist の設定（Google Sign-In用）

`GoogleService-Info.plist` から `REVERSED_CLIENT_ID` をコピーして、
Xcode で Info.plist を開き、以下を追加：

1. プロジェクト設定 → Info タブ
2. `URL Types` セクションを展開
3. `+` ボタンをクリック
4. URL Schemes に `REVERSED_CLIENT_ID` の値を追加
   （例: `com.googleusercontent.apps.123456789-abcdefg`）

または、Info.plist に直接追加：

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

## 🚀 アプリの起動

1. Xcode でプロジェクトをクリーンビルド: `⌥⇧⌘K`
2. ビルド: `⌘B`
3. 実行: `⌘R`

## ✅ 動作確認

### 新規登録

1. アプリを起動
2. 「新規登録はこちら」をタップ
3. メールアドレスとパスワードを入力（6文字以上）
4. 「登録」をタップ

### Google Sign-In

1. 「Googleでログイン」をタップ
2. Googleアカウントを選択
3. 許可

### データ移行

初回ログイン時、ローカルデータがある場合：
- データ移行画面が表示されます
- 「移行する」をタップするとFirestoreに移行
- 「スキップ」で移行をスキップ可能

## 🔧 トラブルシューティング

### ビルドエラー: "No such module 'FirebaseAuth'"

1. File → Packages → Reset Package Caches
2. Product → Clean Build Folder (⌥⇧⌘K)
3. 再ビルド

### Google Sign-In が動作しない

1. `GoogleService-Info.plist` が正しく追加されているか確認
2. Info.plist の URL Schemes が正しいか確認
3. Firebase Console で Google Sign-In が有効になっているか確認

### Firestore の書き込みエラー

1. Firebase Console → Firestore Database → ルール を確認
2. 認証が有効になっているか確認
3. ユーザーが正しくログインしているか確認

## 📱 機能

### ログイン機能
- ✅ メールアドレス＋パスワード認証
- ✅ Google Sign-In
- ✅ パスワードリセット
- ✅ ログアウト

### データ管理
- ✅ ユーザーごとにデータ分離
- ✅ Firestore クラウド同期
- ✅ ローカルデータの自動移行
- ✅ リアルタイムデータ読み込み

### セキュリティ
- ✅ ユーザー認証必須
- ✅ 自分のデータのみアクセス可能
- ✅ Firestore セキュリティルール

## 📝 注意事項

- `GoogleService-Info.plist` は絶対にコミットしないでください（`.gitignore` に追加済み）
- Firebase の無料プランでは制限があります:
  - Firestore: 1日あたり50,000回の読み取り
  - Authentication: 無制限
- 本番環境では適切なセキュリティルールを設定してください

## 🔗 参考リンク

- [Firebase Documentation](https://firebase.google.com/docs/ios/setup)
- [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios/start-integrating)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)

