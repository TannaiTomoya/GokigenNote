//
//  QueueTier.swift
//  GokigenNote
//
//  API・UI用。subscription_yearly → priority、それ以外 → standard。
//

import Foundation

enum QueueTier: String, Equatable {
    case standard
    case priority
}
