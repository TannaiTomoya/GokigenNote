//
//  AuthURLHandler.swift
//  GokigenNote
//
//  Google ログイン等の OAuth リダイレクト（カスタム URL スキーム）は
//  GokigenNoteApp の WindowGroup に付与した .onOpenURL で処理しています。
//  （iOS 26 で非推奨の UIApplicationDelegate open url の代わりに UIScene / SwiftUI .onOpenURL を使用）
//

import UIKit
import FirebaseAuth

/// 必要に応じて UIApplicationDelegate の他の処理を追加するためのクラス。
/// URL オープンは GokigenNoteApp の .onOpenURL で行う。
final class AppDelegateForAuth: NSObject, UIApplicationDelegate {}
