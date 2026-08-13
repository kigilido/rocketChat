//
//  ConversationStore.swift
//  RocketChat
//

import Foundation
import SwiftData

/// Finds or creates the local (cached) conversation that mirrors a Supabase room.
enum ConversationStore {
    /// Look up a conversation by its shared room key, creating one when absent.
    static func conversation(
        forRoomKey roomKey: String,
        title: String,
        kind: TagKind,
        myHandle: String,
        ttl: ConversationTTL,
        context: ModelContext
    ) -> Conversation {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.roomKey == roomKey }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.title = title
            return existing
        }

        let conversation = Conversation(
            title: title,
            kind: kind,
            myHandle: myHandle,
            ttl: ttl,
            roomKey: roomKey
        )
        context.insert(conversation)
        return conversation
    }
}
