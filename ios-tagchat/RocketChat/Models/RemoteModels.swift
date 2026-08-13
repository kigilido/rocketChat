//
//  RemoteModels.swift
//  RocketChat
//
//  Codable mirrors of the Supabase tables. All are `nonisolated` + `Sendable`
//  because PostgREST decodes them off the main actor.
//

import Foundation

// MARK: - Profile

nonisolated struct Profile: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let username: String
    let phoneLast4: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case phoneLast4 = "phone_last4"
    }
}

nonisolated struct ProfileUsernameUpdate: Encodable, Sendable {
    let username: String
}

// MARK: - Contact handles

nonisolated struct ContactHandles: Codable, Sendable, Equatable {
    var instagram: String?
    var whatsapp: String?
    var telegram: String?
    var other: String?

    static let empty = ContactHandles(instagram: nil, whatsapp: nil, telegram: nil, other: nil)

    var isEmpty: Bool {
        [instagram, whatsapp, telegram, other]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .allSatisfy(\.isEmpty)
    }
}

nonisolated struct ContactHandlesUpsert: Encodable, Sendable {
    let userId: UUID
    let instagram: String?
    let whatsapp: String?
    let telegram: String?
    let other: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case instagram
        case whatsapp
        case telegram
        case other
    }
}

/// Row returned by the `get_room_contacts` RPC once a request is accepted.
nonisolated struct RevealedContact: Codable, Identifiable, Sendable, Equatable {
    let userId: UUID
    let username: String
    let instagram: String?
    let whatsapp: String?
    let telegram: String?
    let other: String?

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case instagram
        case whatsapp
        case telegram
        case other
    }

    /// Non-empty handles as (label, value, url) tuples for rendering.
    var links: [(label: String, value: String, url: URL?)] {
        var result: [(String, String, URL?)] = []
        if let handle = instagram?.normalizedHandle {
            result.append(("Instagram", "@\(handle)", URL(string: "https://instagram.com/\(handle)")))
        }
        if let handle = whatsapp?.normalizedHandle {
            let digits = handle.filter(\.isNumber)
            result.append(("WhatsApp", handle, URL(string: "https://wa.me/\(digits)")))
        }
        if let handle = telegram?.normalizedHandle {
            result.append(("Telegram", "@\(handle)", URL(string: "https://t.me/\(handle)")))
        }
        if let handle = other?.trimmingCharacters(in: .whitespaces), !handle.isEmpty {
            result.append(("Other", handle, nil))
        }
        return result
    }
}

extension String {
    /// Strip decorations users habitually type into handle fields.
    var normalizedHandle: String? {
        let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        return cleaned.isEmpty ? nil : cleaned
    }
}

// MARK: - Rooms

nonisolated struct Room: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let roomKey: String
    let kind: String
    let label: String
    let dropId: UUID?
    let createdAt: Date?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomKey = "room_key"
        case kind
        case label
        case dropId = "drop_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

nonisolated struct RoomInsert: Encodable, Sendable {
    let roomKey: String
    let kind: String
    let label: String
    let dropId: UUID?
    let createdBy: UUID
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case roomKey = "room_key"
        case kind
        case label
        case dropId = "drop_id"
        case createdBy = "created_by"
        case expiresAt = "expires_at"
    }
}

nonisolated struct RoomMemberInsert: Encodable, Sendable {
    let roomId: UUID
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case userId = "user_id"
    }
}

// MARK: - Messages

nonisolated struct RemoteMessage: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let roomId: UUID
    let senderId: UUID?
    let kind: String
    let body: String?
    let audioPath: String?
    let duration: Double?
    let reactions: [String: [String]]
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case senderId = "sender_id"
        case kind
        case body
        case audioPath = "audio_path"
        case duration
        case reactions
        case createdAt = "created_at"
    }

    var isVoice: Bool { kind == "voice" }
}

nonisolated struct MessageInsert: Encodable, Sendable {
    let id: UUID
    let roomId: UUID
    let senderId: UUID
    let kind: String
    let body: String?
    let audioPath: String?
    let duration: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case senderId = "sender_id"
        case kind
        case body
        case audioPath = "audio_path"
        case duration
    }
}

nonisolated struct MessageReactionsUpdate: Encodable, Sendable {
    let reactions: [String: [String]]
}

// MARK: - Contact requests

nonisolated enum ContactRequestStatus: String, Codable, Sendable {
    case pending
    case accepted
    case declined
}

nonisolated struct ContactRequest: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let roomId: UUID
    let requesterId: UUID
    let status: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case requesterId = "requester_id"
        case status
        case createdAt = "created_at"
    }

    var state: ContactRequestStatus { ContactRequestStatus(rawValue: status) ?? .pending }
}

nonisolated struct ContactRequestInsert: Encodable, Sendable {
    let roomId: UUID
    let requesterId: UUID

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case requesterId = "requester_id"
    }
}

nonisolated struct ContactRequestResolve: Encodable, Sendable {
    let status: String
    let resolvedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case resolvedAt = "resolved_at"
    }
}

// MARK: - Drops

nonisolated struct Drop: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let authorId: UUID
    let category: String
    let title: String
    let body: String?
    let lat: Double
    let lng: Double
    let replyCount: Int
    let createdAt: Date?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case authorId = "author_id"
        case category
        case title
        case body
        case lat
        case lng
        case replyCount = "reply_count"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    var dropCategory: DropCategory { DropCategory(rawValue: category) ?? .question }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}

nonisolated struct DropInsert: Encodable, Sendable {
    let authorId: UUID
    let category: String
    let title: String
    let body: String?
    let lat: Double
    let lng: Double
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case authorId = "author_id"
        case category
        case title
        case body
        case lat
        case lng
        case expiresAt = "expires_at"
    }
}

nonisolated struct DropReply: Codable, Identifiable, Sendable {
    let id: UUID
    let dropId: UUID
    let userId: UUID
    let roomId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case dropId = "drop_id"
        case userId = "user_id"
        case roomId = "room_id"
    }
}

nonisolated struct DropReplyInsert: Encodable, Sendable {
    let dropId: UUID
    let userId: UUID
    let roomId: UUID

    enum CodingKeys: String, CodingKey {
        case dropId = "drop_id"
        case userId = "user_id"
        case roomId = "room_id"
    }
}
