//
//  User.swift
//  GokigenNote
//
//  Created by 丹内智弥 on 2025/11/22.
//

import Foundation

struct User: Identifiable, Codable {
    var id: String // Firebase UID
    var email: String?
    var displayName: String?
    var createdAt: Date
    
    init(id: String, email: String?, displayName: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.createdAt = Date()
    }
}

