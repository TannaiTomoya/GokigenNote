//
//  APIKey.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/20.
//

import Foundation

enum APIKey {
    static var gemini: String? {
        guard let filePath = Bundle.main.path(forResource: "Gemini-Info", ofType: "plist") else {
            return nil
        }
        guard let plist = NSDictionary(contentsOfFile: filePath),
              let value = plist.object(forKey: "API_KEY") as? String else {
            return nil
        }
        return value
    }
}
