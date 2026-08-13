//
//  TagKind.swift
//  RocketChat
//

import SwiftUI

/// The kind of real-world identifier a tag was created from.
enum TagKind: String, Codable, CaseIterable, Identifiable {
    case licensePlate
    case qrCode
    case sign
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .licensePlate: return "License Plate"
        case .qrCode: return "QR Code"
        case .sign: return "Sign"
        case .text: return "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .licensePlate: return "car.fill"
        case .qrCode: return "qrcode"
        case .sign: return "signpost.right.fill"
        case .text: return "textformat"
        }
    }

    var tint: Color {
        switch self {
        case .licensePlate: return Theme.accent
        case .qrCode: return Theme.cyan
        case .sign: return Color(hex: 0xFFB84D)
        case .text: return Color(hex: 0xB98CFF)
        }
    }
}
