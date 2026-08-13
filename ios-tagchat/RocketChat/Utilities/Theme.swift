//
//  Theme.swift
//  RocketChat
//
//  Centralised colours, gradients and metrics for a cohesive look.
//

import SwiftUI

/// App-wide design tokens. RocketChat uses a dark "scanner" aesthetic with an
/// electric-lime primary accent and a cyan secondary for depth.
enum Theme {
    // Backgrounds
    static let background = Color(hex: 0x0A0B10)
    static let surface = Color(hex: 0x14161F)
    static let surfaceElevated = Color(hex: 0x1C1F2B)

    // Accents
    static let accent = Color(hex: 0xC6FF4D)
    static let accentSoft = Color(hex: 0xC6FF4D).opacity(0.16)
    static let cyan = Color(hex: 0x4DE1FF)

    // Text
    static let textPrimary = Color(hex: 0xF4F6FB)
    static let textSecondary = Color(hex: 0x9AA0B2)
    static let textTertiary = Color(hex: 0x5C6072)

    // Status
    static let danger = Color(hex: 0xFF5C72)

    static let cornerRadius: CGFloat = 18

    /// Subtle vertical wash used behind most screens for atmosphere.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x0C0E15), background],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The signature accent gradient used on primary actions and highlights.
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    /// Create a colour from a 24-bit hex literal, e.g. `Color(hex: 0xC6FF4D)`.
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
