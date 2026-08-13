//
//  Conversation.swift
//  RocketChat
//

import Foundation
import SwiftData

/// An anonymous conversation thread tied to a scanned identifier.
@Model
final class Conversation {
    @Attribute(.unique) var id: UUID
    /// Masked label shown in the UI (e.g. "Plate ••• 7G4").
    var title: String
    var kindRaw: String
    var createdAt: Date
    var lastActivityAt: Date
    /// The anonymous handle the local user is using in this thread.
    var myHandle: String
    /// TTL in seconds. 0 means forever.
    var ttlSeconds: Int
    /// Stable shared key used to resolve the Supabase room two devices join.
    var roomKey: String?
    /// Cached Supabase room id once resolved.
    var remoteRoomID: String?

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(
        id: UUID = UUID(),
        title: String,
        kind: TagKind,
        myHandle: String,
        ttl: ConversationTTL = .day,
        createdAt: Date = .now,
        roomKey: String? = nil,
        remoteRoomID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.myHandle = myHandle
        self.roomKey = roomKey
        self.remoteRoomID = remoteRoomID
        self.ttlSeconds = ttl.rawValue
        self.createdAt = createdAt
        self.lastActivityAt = createdAt
        self.messages = []
    }

    var kind: TagKind {
        TagKind(rawValue: kindRaw) ?? .text
    }

    var ttl: ConversationTTL {
        get { ConversationTTL(rawValue: ttlSeconds) ?? .forever }
        set { ttlSeconds = newValue.rawValue }
    }

    var isEphemeral: Bool {
        ttlSeconds > 0
    }

    var expiresAt: Date? {
        guard ttlSeconds > 0 else { return nil }
        return Date(timeIntervalSince1970: createdAt.timeIntervalSince1970 + TimeInterval(ttlSeconds))
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }

    var timeRemaining: TimeInterval {
        guard let expiresAt else { return .infinity }
        return max(0, expiresAt.timeIntervalSinceNow)
    }

    var sortedMessages: [Message] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }

    var lastMessagePreview: String {
        if let last = sortedMessages.last {
            if last.isVoiceMessage {
                return "🎙 Voice note"
            }
            return last.text
        }
        return "Say hello anonymously"
    }
}
