//
//  IdentityStore.swift
//  RocketChat
//

import Foundation
import SwiftUI

/// Manages the local user's anonymous identity. No account, no PII — just a
/// rotating, friendly handle persisted locally.
@Observable
final class IdentityStore {
    private let handleKey = "tagchat.handle"
    private let ghostModeKey = "tagchat.ghostMode"
    private let voiceMaskingKey = "tagchat.voiceMasking"
    private let defaultTTLKey = "tagchat.defaultTTL"
    private let dropRadiusKey = "tagchat.dropRadius"
    private let defaults = UserDefaults.standard

    private(set) var handle: String
    var ghostMode: Bool {
        didSet { defaults.set(ghostMode, forKey: ghostModeKey) }
    }
    var voiceMaskingEnabled: Bool {
        didSet { defaults.set(voiceMaskingEnabled, forKey: voiceMaskingKey) }
    }
    var defaultTTL: ConversationTTL {
        didSet { defaults.set(defaultTTL.rawValue, forKey: defaultTTLKey) }
    }
    /// How far out street drops stay visible on the Drops and Map tabs.
    var dropRadius: DropRadius {
        didSet { defaults.set(dropRadius.rawValue, forKey: dropRadiusKey) }
    }

    init() {
        if let saved = defaults.string(forKey: handleKey) {
            handle = saved
        } else {
            let generated = Self.randomHandle()
            handle = generated
            defaults.set(generated, forKey: handleKey)
        }
        ghostMode = defaults.bool(forKey: ghostModeKey)
        voiceMaskingEnabled = defaults.bool(forKey: voiceMaskingKey)
        let ttlRaw = defaults.integer(forKey: defaultTTLKey)
        defaultTTL = ConversationTTL(rawValue: ttlRaw) ?? .day

        // Absent key reads as 0, which is the `.global` case — fall back to the
        // neighbourhood default only when nothing was ever stored.
        if defaults.object(forKey: dropRadiusKey) == nil {
            dropRadius = .neighbourhood
        } else {
            dropRadius = DropRadius(rawValue: defaults.integer(forKey: dropRadiusKey)) ?? .neighbourhood
        }
    }

    /// Generate and persist a brand-new anonymous handle.
    func reroll() {
        let generated = Self.randomHandle()
        handle = generated
        defaults.set(generated, forKey: handleKey)
    }

    private static let adjectives = [
        "Crimson", "Silent", "Neon", "Velvet", "Hidden", "Electric",
        "Lunar", "Amber", "Static", "Cobalt", "Quiet", "Phantom"
    ]
    private static let animals = [
        "Fox", "Heron", "Lynx", "Moth", "Otter", "Raven",
        "Wolf", "Koi", "Falcon", "Mantis", "Stag", "Orca"
    ]

    private static func randomHandle() -> String {
        let adjective = adjectives.randomElement() ?? "Quiet"
        let animal = animals.randomElement() ?? "Fox"
        let number = Int.random(in: 100...999)
        return "\(adjective) \(animal) \(number)"
    }
}
