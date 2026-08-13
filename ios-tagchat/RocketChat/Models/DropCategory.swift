//
//  DropCategory.swift
//  RocketChat
//

import SwiftUI

/// The flavour of a street drop. Drives pin colour, icon and copy.
nonisolated enum DropCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case question
    case alert
    case note
    case event

    var id: String { rawValue }

    var title: String {
        switch self {
        case .question: return "Question"
        case .alert: return "Alert"
        case .note: return "Note"
        case .event: return "Event"
        }
    }

    var systemImage: String {
        switch self {
        case .question: return "questionmark.bubble.fill"
        case .alert: return "exclamationmark.triangle.fill"
        case .note: return "mappin.and.ellipse"
        case .event: return "calendar"
        }
    }

    var placeholder: String {
        switch self {
        case .question: return "Is the parking here free after 6pm?"
        case .alert: return "Construction blocking the sidewalk"
        case .note: return "Great coffee spot around the corner"
        case .event: return "Farmers market every Saturday"
        }
    }

    @MainActor var tint: Color {
        switch self {
        case .question: return Theme.cyan
        case .alert: return Theme.danger
        case .note: return Theme.accent
        case .event: return Color(hex: 0xFFB84D)
        }
    }
}

/// How far out street drops stay visible. Persisted in Settings.
nonisolated enum DropRadius: Int, Codable, CaseIterable, Identifiable, Sendable {
    case near = 500
    case neighbourhood = 2_000
    case city = 10_000
    case global = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .near: return "500 m"
        case .neighbourhood: return "2 km"
        case .city: return "10 km"
        case .global: return "Global"
        }
    }

    var subtitle: String {
        switch self {
        case .near: return "This block only"
        case .neighbourhood: return "Around the neighbourhood"
        case .city: return "Across the city"
        case .global: return "Everywhere, no distance filter"
        }
    }

    /// Distance limit in metres, or nil when unbounded.
    var metres: Double? {
        self == .global ? nil : Double(rawValue)
    }
}
