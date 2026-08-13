//
//  ConversationTTL.swift
//  RocketChat
//

import Foundation

/// Lifespan options for ephemeral conversations. Reinforces the privacy
/// promise: chats disappear automatically after the chosen window.
enum ConversationTTL: Int, Codable, CaseIterable, Identifiable {
    /// Auto-delete after 24 hours.
    case day = 86_400
    /// Auto-delete after 7 days.
    case week = 604_800
    /// Keep indefinitely (user must delete manually).
    case forever = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .day: return "24h"
        case .week: return "7d"
        case .forever: return "Keep"
        }
    }

    var descriptiveLabel: String {
        switch self {
        case .day: return "Expires in 24 hours"
        case .week: return "Expires in 7 days"
        case .forever: return "Kept until you delete it"
        }
    }

    var systemImage: String {
        switch self {
        case .day: return "clock"
        case .week: return "calendar"
        case .forever: return "infinity"
        }
    }

    var seconds: TimeInterval {
        guard rawValue > 0 else { return .infinity }
        return TimeInterval(rawValue)
    }
}
