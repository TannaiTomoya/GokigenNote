# ごきげんノート

日々の気分を記録し、やさしい言葉で振り返ることができるメンタルケアアプリです。

## 📱 主な機能

### 🔐 認証
- Firebase Authentication（メール/パスワード、Google Sign-In）
- 未ログイン時は AuthView、ログイン後は MainTabView

### ✨ 今日の問い（メイン）
- 場面・気分選択、テキストまたは**音声入力**で「言いたいこと」を入力
- **言い換え**：Gemini API でやさしい表現に変換（送る／もう一度調整／記録する）
- **DraftSession**：編集中1件を Firestore にオートセーブ（upsert）、記録で確定
- 共通枠（言い換え・共感の合算）の**回数制限**表示

### 💬 言い換え・共感
- Google Gemini API で言い換え・共感メッセージ生成
- 無料は1日10回、買い切りは月200回、サブスクは無制限（PremiumManager）

### 📊 トレーニング
- 脳トレ系ミニゲーム（N-back、数字記憶、逆記憶など）とトレーニング履歴

### 📅 カレンダー・記録
- カレンダー表示、履歴一覧（HistoryListView）、エントリ詳細

### 💾 データ
- **Firestore**：ログイン後の記録（users/{uid}/entries）、DraftSession の upsert
- **課金状態**：StoreKit 2、Firebase Functions の `syncEntitlements` でサーバと同期

### 🛒 課金（Paywall）
- 無料 / 月額・年額サブスク / 買い切り（Lifetime）
- PaywallCoordinator で PaywallView をシート表示

## 🛠️ 技術スタック

- **UI**: SwiftUI（iOS）
- **認証**: Firebase Auth
- **DB**: Firebase Firestore
- **課金**: StoreKit 2、Firebase Functions（syncEntitlements）
- **AI**: Google Gemini API（GoogleGenerativeAI SPM）
- **音声**: Speech framework、AVAudioEngine（iOS のみ AVAudioSession）
- **アーキテクチャ**: MVVM

## 📂 プロジェクト構造（抜粋）

```
GokigenNote/
├── GokigenNoteApp.swift/
│   ├── GokigenNoteApp.swift   # エントリポイント（FirebaseCore, PremiumManager.start, Paywall）
│   └── ContentView.swift      # TodayView（今日の問い・言い換え・音声・記録）
├── Models/
│   ├── Entry.swift            # 記録エントリ
│   ├── DraftSession.swift    # 編集中1件・AutoSaveState・Firestore upsert用
│   ├── Mood.swift             # 気分
│   ├── ReformulationContext.swift
│   ├── TrendSnapshot.swift
│   └── ...
├── Views/
│   ├── MainTabView.swift      # タブ: 今日の問い / トレーニング / カレンダー / 記録 / 設定
│   ├── AuthView.swift
│   ├── PaywallView.swift
│   ├── HistoryListView.swift, CalendarView.swift, EntryDetailView.swift
│   ├── SettingsView.swift
│   └── Training/              # トレーニング関連
├── ViewModels/
│   ├── GokigenViewModel.swift # メインVM（DraftSession, 言い換え, 保存, 履歴）
│   ├── AuthViewModel.swift
│   └── TrainingViewModel.swift
└── Services/
    ├── FirestoreService.swift # users/entries upsert, DraftSession, 履歴取得
    ├── PremiumManager.swift   # 課金・共通枠（rewriteQuota）
    ├── GeminiService.swift    # Gemini API
    ├── SpeechInputService.swift # 音声→テキスト
    ├── AuthService.swift, AuthGate.swift
    ├── PaywallCoordinator.swift
    └── ...
```

## 🔧 セットアップ

### 1. リポジトリと Xcode

```bash
git clone <repository-url>
cd GokigenNote-1
open GokigenNote.xcodeproj
```

- **File → Packages → Resolve Package Versions** で SPM 解決（Firebase iOS SDK, Google Generative AI Swift）

### 2. Firebase

- Firebase プロジェクトで iOS アプリを追加し、`GoogleService-Info.plist` を配置
- Authentication（メール/パスワード、Google）と Firestore、Functions（`syncEntitlements`）を有効化
- 詳細は `FIREBASE_SETUP.md` を参照

### 3. Gemini API（言い換え・共感）

- [Google AI Studio](https://aistudio.google.com/apikey) で API キーを取得
- Xcode の Run スキームの **Environment Variables** に `GEMINI_API_KEY` を設定  
  または `Gemini-Info.plist` の `API_KEY` で設定（`.gitignore` 済み）

### 4. ビルド・実行

- 対象: **iOS**（シミュレータまたは実機）
- ⌘R で実行。未ログインなら AuthView、ログイン後は MainTabView。

## 📝 使い方（今日の問い）

1. ログイン後、「今日の問い」タブで場面・気分を選択
2. 「話す」で音声入力、またはテキストで入力
3. 「言い換えをつくる」でやさしい表現を生成（共通枠を1消費）
4. 送る／もう一度調整／**記録する**で Firestore に保存（Draft はオートセーブ）
5. 記録・カレンダー・トレーニング・設定は各タブから利用

## 🔒 プライバシー・利用

- ログイン後の記録は Firestore に保存されます
- 言い換え・共感は **Google Gemini API** にテキストを送信します（[利用規約](https://ai.google.dev/terms)・[プライバシー](https://policies.google.com/privacy)に従います）
- 課金状態は StoreKit と Firebase Functions でサーバと同期します

## 📄 ライセンス・注意

- 教育目的で作成されたプロジェクトです
- メンタルヘルスの専門的サポートは提供しません。深刻な悩みは専門機関にご相談ください

## 👤 作成者

丹内智弥 (Tomoya Tannai)
