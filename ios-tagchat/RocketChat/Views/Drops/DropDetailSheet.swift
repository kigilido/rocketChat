//
//  DropDetailSheet.swift
//  RocketChat
//

import SwiftUI

struct DropDetailSheet: View {
    let drop: Drop
    let distance: String?
    var isBusy: Bool = false
    let onReply: () -> Void

    @Environment(AuthService.self) private var auth

    private var isMine: Bool { auth.userID == drop.authorId }

    private var actionTitle: String {
        guard isMine else { return "Reply privately" }
        return drop.replyCount > 0 ? "Open latest reply" : "No replies yet"
    }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header

                if let body = drop.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                metadata

                Spacer(minLength: 0)

                PrimaryActionButton(
                    title: actionTitle,
                    isBusy: isBusy,
                    isEnabled: !isMine || drop.replyCount > 0,
                    action: onReply
                )

                Label(
                    isMine
                        ? "Each reply arrives as its own confidential thread in Chats."
                        : "Only the person who dropped this sees your reply.",
                    systemImage: "lock.fill"
                )
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(drop.dropCategory.tint.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: drop.dropCategory.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(drop.dropCategory.tint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(drop.dropCategory.title.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(drop.dropCategory.tint)

                Text(drop.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            if let distance {
                MetaPill(icon: "location.fill", text: distance, tint: Theme.cyan)
            }
            if drop.replyCount > 0 {
                MetaPill(icon: "bubble.left.fill", text: "\(drop.replyCount)", tint: Theme.accent)
            }
            if let createdAt = drop.createdAt {
                MetaPill(
                    icon: "clock",
                    text: createdAt.formatted(.relative(presentation: .named)),
                    tint: Theme.textSecondary
                )
            }
            Spacer(minLength: 0)
        }
    }
}

private struct MetaPill: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surfaceElevated, in: Capsule())
    }
}
