//
//  ChatListView.swift
//  RocketChat
//

import SwiftUI
import SwiftData

/// The Chat tab. Lists all anonymous conversations started from scanned tags.
struct ChatListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.lastActivityAt, order: .reverse)
    private var conversations: [Conversation]

    /// Optional conversation to deep-link into (e.g. right after a scan).
    @Binding var route: Conversation?

    private var activeConversations: [Conversation] {
        conversations.filter { !$0.isExpired }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if activeConversations.isEmpty {
                    EmptyChatState()
                } else {
                    list
                }
            }
            .navigationTitle("Chats")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: Conversation.self) { conversation in
                ConversationView(conversation: conversation)
            }
            .navigationDestination(item: $route) { conversation in
                ConversationView(conversation: conversation)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(activeConversations) { conversation in
                    NavigationLink(value: conversation) {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(conversation.kind.tint.opacity(0.16))
                    .frame(width: 52, height: 52)
                Image(systemName: conversation.kind.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(conversation.kind.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(conversation.title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if conversation.isEphemeral {
                        EphemeralTag(conversation: conversation)
                    }
                }
                Text(conversation.lastMessagePreview)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(conversation.lastActivityAt, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Small pill showing the ephemeral status of a conversation.
private struct EphemeralTag: View {
    let conversation: Conversation

    private var remaining: TimeInterval {
        conversation.timeRemaining
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.fill")
                .font(.system(size: 8))
            Text(remaining < 3600 ? "<1h" : conversation.ttl.label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(remaining < 3600 ? Theme.danger : Theme.cyan)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            (remaining < 3600 ? Theme.danger.opacity(0.15) : Theme.cyan.opacity(0.12)),
            in: Capsule()
        )
    }
}

private struct EmptyChatState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("No chats yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Scan a license plate, QR code, or sign\nto start an anonymous conversation.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
