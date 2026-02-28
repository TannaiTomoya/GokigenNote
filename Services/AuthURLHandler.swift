//
//  AuthURLHandler.swift
//  GokigenNote
//
//  Google ログイン等の OAuth リダイレクト（カスタム URL スキーム）を受け取り、
//  Firebase Auth に渡すための App Delegate。
//  about:blank のままになる場合は、@main の App で UIApplicationDelegateAdaptor(AppDelegateForAuth.self) を指定してください。
//

import UIKit
import FirebaseAuth

final class AppDelegateForAuth: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return Auth.auth().canHandle(url)
    }
}
