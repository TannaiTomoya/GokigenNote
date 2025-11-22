//
//  APIKey.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/20.
//

import Foundation

enum APIKey {
    static var gemini: String? {
        // 1. まず環境変数をチェック
        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
           !envKey.isEmpty,
           envKey != "YOUR_GEMINI_API_KEY_HERE" {
            return envKey
        }
        
        // 2. 環境変数がなければplistから読み取る
        guard let filePath = Bundle.main.path(forResource: "Gemini-Info", ofType: "plist") else {
            return nil
        }
        guard let plist = NSDictionary(contentsOfFile: filePath),
            let value = plist.object(forKey: "API_KEY") as? String,
            value != "YOUR_GEMINI_API_KEY_HERE" else {
            return nil
        }
        return value
    }
}
