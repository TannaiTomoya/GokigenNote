# セットアップ手順

## Gemini API キー

**Gemini キー:** .gitignore の plist か環境変数で設定。リポジトリには .example のみ。本番は Functions 推奨。

- 手元のみで使う場合: `Gemini-Info.plist.example` をコピーして `Gemini-Info.plist` を作成し API_KEY を設定（`Gemini-Info.plist` は `.gitignore` に含まれるため Git にコミットされません）
- または環境変数 `GEMINI_API_KEY` を設定
- 言い換え／共感は Functions 経由のため、本番では iOS にキーを置かず Functions 側で管理する運用を推奨

## Firebase

（必要な場合は GoogleService-Info.plist の取得手順などを記載）
