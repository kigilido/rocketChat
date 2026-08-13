//
//  ConversationView.swift
//  RocketChat
//

import SwiftUI
import SwiftData
import Combine

/// A single anonymous conversation thread.
struct ConversationView: View {
    @Bindable var conversation: Conversation
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioService.self) private var audio
    @Environment(AuthService.self) private var auth

    @State private var draft: String = ""
    @State private var showQuickReplies: Bool = false
    @State private var reactionTarget: Message?
    @State private var now: Date = .now
    @State private var session: RoomSession?
    @State private var isRequestingContact: Bool = false

    private let quickReplies: [String] = [
        "Hey 👋", "Thanks!", "On my way", "Be right back",
        "👍", "❤️", "😂", "Sorry about that"
    ]

    private let reactionEmojis: [String] = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                if conversation.isEphemeral {
                    EphemeralCountdownBar(conversation: conversation, now: now)
                }
                if session?.isOffline == true {
                    OfflineBar()
                }
                messages
                composer
            }
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ContactRequestButton(state: session?.contactState ?? .none) {
                    isRequestingContact = true
                }
            }
        }
        .confirmationDialog(
            "Share contact info?",
            isPresented: $isRequestingContact,
            titleVisibility: .visible
        ) {
            Button("Send request") {
                Task { await session?.requestContact() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll be asked to swap social handles. Nothing is revealed unless you both agree.")
        }
        .task {
            audio.stopPlayback()
            guard session == nil, let userID = auth.userID else { return }
            let newSession = RoomSession(
                conversation: conversation,
                context: modelContext,
                myUserID: userID,
                myUsername: auth.profile?.username ?? conversation.myHandle
            )
            session = newSession
            await newSession.start()
        }
        .onDisappear {
            audio.stopPlayback()
            session?.stop()
        }
        // Tick the clock every second for the countdown
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { time in
            now = time
        }
        .sheet(item: $reactionTarget) { message in
            ReactionPicker(emojis: reactionEmojis) { emoji in
                Task { await session?.toggleReaction(emoji, on: message) }
                reactionTarget = nil
            }
            .presentationDetents([.height(120)])
            .presentationDragIndicator(.visible)
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    PrivacyBanner()
                        .padding(.bottom, 4)
                    ForEach(conversation.sortedMessages) { message in
                        MessageBubble(
                            message: message,
                            onLongPress: { reactionTarget = message }
                        )
                        .id(message.id)
                    }

                    if let session {
                        ContactExchangeSection(session: session)
                            .padding(.top, 4)
                            .id("contact-exchange")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                if let last = conversation.sortedMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if showQuickReplies {
                QuickReplyBar(replies: quickReplies) { reply in
                    send(text: reply)
                    showQuickReplies = false
                }
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        showQuickReplies.toggle()
                    }
                } label: {
                    Image(systemName: showQuickReplies ? "xmark" : "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(Theme.surfaceElevated, in: Circle())
                }

                VoiceRecordButton { url, duration in
                    sendVoiceNote(url: url, duration: duration)
                }

                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Theme.surfaceElevated, in: Capsule())
                    .lineLimit(1...4)

                Button(action: { send(text: draft) }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(canSend ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.textTertiary), in: Circle())
                }
                .disabled(!canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private func sendVoiceNote(url: URL, duration: TimeInterval) {
        Task { await session?.sendVoiceNote(url: url, duration: duration) }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = ""
        Task { await session?.send(text: trimmed) }
    }
}

// MARK: - Ephemeral Countdown

/// A slim bar at the top of an ephemeral conversation showing the time
/// remaining before the chat auto-expires.
private struct EphemeralCountdownBar: View {
    let conversation: Conversation
    let now: Date

    private var remaining: TimeInterval {
        max(0, conversation.timeRemaining)
    }

    private var progress: Double {
        guard let expiresAt = conversation.expiresAt, conversation.ttlSeconds > 0 else { return 0 }
        let total = TimeInterval(conversation.ttlSeconds)
        let elapsed = expiresAt.timeIntervalSinceNow
        return max(0, min(1, 1 - (-elapsed / total)))
    }

    private var timeLabel: String {
        guard remaining.isFinite else { return "" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s left"
        } else {
            return "\(seconds)s left"
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                Text(timeLabel)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(remaining < 3600 ? Theme.danger : Theme.cyan)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.surfaceElevated)
                        .frame(height: 2)
                    Rectangle()
                        .fill(remaining < 3600 ? Theme.danger : Theme.cyan)
                        .frame(width: geo.size.width * (1 - progress), height: 2)
                }
            }
            .frame(height: 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Theme.surface.opacity(0.5))
    }
}

// MARK: - Quick Replies

private struct QuickReplyBar: View {
    let replies: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(replies, id: \.self) { reply in
                    Button { onSelect(reply) } label: {
                        Text(reply)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.surfaceElevated, in: Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(height: 52)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Voice Record Button

private struct VoiceRecordButton: View {
    @Environment(AudioService.self) private var audio

    /// Called with the recorded file URL and duration when recording stops.
    var onSend: (URL, TimeInterval) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isCancelArmed: Bool = false

    private let cancelThreshold: CGFloat = -60

    var body: some View {
        if audio.isRecording {
            recordingState
        } else {
            startButton
        }
    }

    private var startButton: some View {
        Button {
            _ = audio.startRecording()
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 38, height: 38)
                .background(Theme.surfaceElevated, in: Circle())
        }
    }

    private var recordingState: some View {
        ZStack {
            Capsule()
                .fill(isCancelArmed ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.accentSoft))
                .frame(height: 38)

            HStack(spacing: 6) {
                if isCancelArmed {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                    Text("Release to cancel")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                } else {
                    RecordingPulse()
                    Text(formatDuration(audio.recordingDuration))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text("<< Slide to cancel")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(width: isCancelArmed ? 140 : 180)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.width
                    isCancelArmed = dragOffset < cancelThreshold
                }
                .onEnded { _ in
                    if isCancelArmed {
                        audio.cancelRecording()
                    } else {
                        stopAndSend()
                    }
                    dragOffset = 0
                    isCancelArmed = false
                }
        )
    }

    private func stopAndSend() {
        guard let result = audio.stopRecording() else { return }
        onSend(result.url, result.duration)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct RecordingPulse: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(Theme.danger)
            .frame(width: 10, height: 10)
            .scaleEffect(scale)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: scale)
            .onAppear { scale = 1.4 }
    }
}

// MARK: - Reaction Picker

private struct ReactionPicker: View {
    let emojis: [String]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(emojis, id: \.self) { emoji in
                Button { onSelect(emoji) } label: {
                    Text(emoji)
                        .font(.title2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(Theme.surface)
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: Message
    var onLongPress: () -> Void

    @Environment(AudioService.self) private var audio

    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 48) }

            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 3) {
                if message.isVoiceMessage {
                    voiceContent
                } else {
                    textContent
                }

                if !message.reactions.isEmpty {
                    ReactionsRow(reactions: message.reactions)
                }

                Text(message.timestamp, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            if !message.isMine { Spacer(minLength: 48) }
        }
        .onLongPressGesture(perform: onLongPress)
    }

    private var textContent: some View {
        Text(message.text)
            .font(.body)
            .foregroundStyle(message.isMine ? .black : Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.isMine ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }

    private var voiceContent: some View {
        VoiceMessageBubble(message: message)
    }
}

// MARK: - Voice Message Bubble

private struct VoiceMessageBubble: View {
    let message: Message
    @Environment(AudioService.self) private var audio

    private var isCurrentlyPlaying: Bool {
        audio.isPlaying && audio.playingMessageId == message.id
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if let fileName = message.audioFileName {
                    let url = audio.audioURL(for: fileName)
                    audio.togglePlayback(url: url, messageId: message.id)
                }
            } label: {
                Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(message.isMine ? .black : Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        message.isMine ? Color.white.opacity(0.2) : Theme.accentSoft,
                        in: Circle()
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                if isCurrentlyPlaying {
                    WaveformView(progress: audio.playingProgress)
                        .frame(width: 100, height: 20)
                } else {
                    StaticWaveform()
                        .frame(width: 100, height: 20)
                }
                Text(message.durationLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(message.isMine ? .black.opacity(0.7) : Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            message.isMine ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

private struct StaticWaveform: View {
    private let bars: [CGFloat] = Array(0..<20).map { _ in CGFloat.random(in: 0.3...1.0) }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(bars.indices, id: \.self) { i in
                    Capsule()
                        .fill(Theme.textTertiary)
                        .frame(width: 2, height: geo.size.height * bars[i])
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct WaveformView: View {
    let progress: Double

    private let bars: [CGFloat] = Array(0..<20).map { _ in CGFloat.random(in: 0.3...1.0) }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(bars.indices, id: \.self) { i in
                    Capsule()
                        .fill(Double(i) / Double(bars.count) < progress ? Color.white : Theme.textTertiary)
                        .frame(width: 2, height: geo.size.height * bars[i])
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Reactions Row

private struct ReactionsRow: View {
    let reactions: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(reactions, id: \.self) { emoji in
                Text(emoji)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accentSoft, in: Capsule())
            }
        }
    }
}

// MARK: - Offline Bar

private struct OfflineBar: View {
    var body: some View {
        Label("Reconnecting… new messages may be delayed", systemImage: "wifi.slash")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color(hex: 0xFFB84D))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(hex: 0xFFB84D).opacity(0.12))
    }
}

// MARK: - Contact Request Button

/// Nav-bar affordance whose look tracks the room's contact-sharing state.
private struct ContactRequestButton: View {
    let state: RoomSession.ContactState
    let onRequest: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        switch state {
        case .accepted:
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)

        case .outgoingPending:
            Image(systemName: "person.crop.circle.badge.clock")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFFB84D))

        case .incomingPending:
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFFB84D))
                .scaleEffect(pulse ? 1.12 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

        case .none, .declined:
            Button(action: onRequest) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityLabel("Request contact info")
        }
    }
}

// MARK: - Contact Exchange

/// Renders the contact-request card and, once accepted, the revealed handles.
private struct ContactExchangeSection: View {
    let session: RoomSession

    private let amber = Color(hex: 0xFFB84D)

    var body: some View {
        switch session.contactState {
        case .none:
            EmptyView()

        case .outgoingPending:
            statusCard(
                icon: "paperplane.fill",
                title: "Contact request sent",
                subtitle: "You'll both see handles the moment they accept."
            )

        case let .incomingPending(requestID, from):
            incomingCard(requestID: requestID, from: from)

        case .declined:
            statusCard(
                icon: "hand.raised.fill",
                title: "Request declined",
                subtitle: "You can ask again later."
            )

        case .accepted:
            acceptedCard
        }
    }

    private func incomingCard(requestID: UUID, from: String) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(amber)
                Text("\(from) wants to share contact info")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Accept and you'll each see the social handles the other saved.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await session.resolveContactRequest(id: requestID, accept: false) }
                } label: {
                    Text("Decline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surfaceElevated, in: Capsule())
                }

                Button {
                    Task { await session.resolveContactRequest(id: requestID, accept: true) }
                } label: {
                    Text("Accept")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accentGradient, in: Capsule())
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(amber.opacity(0.35), lineWidth: 1)
        )
        .transition(.scale.combined(with: .opacity))
    }

    private var acceptedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Contact info exchanged", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)

            if session.revealedContacts.isEmpty {
                Text("They haven't saved any handles yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            ForEach(session.revealedContacts) { contact in
                VStack(alignment: .leading, spacing: 8) {
                    Text(contact.username)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)

                    if contact.links.isEmpty {
                        Text("No handles saved.")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }

                    ForEach(contact.links, id: \.label) { link in
                        HandleRow(label: link.label, value: link.value, url: link.url)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.accent.opacity(0.30), lineWidth: 1)
        )
        .transition(.scale.combined(with: .opacity))
    }

    private func statusCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HandleRow: View {
    let label: String
    let value: String
    let url: URL?

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: 10) {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 62, alignment: .leading)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(url == nil ? Theme.textPrimary : Theme.cyan)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }
}

// MARK: - Privacy Banner

private struct PrivacyBanner: View {
    var body: some View {
        Label("Messages are anonymous. Your real identity is never shared.", systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(Theme.cyan)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Theme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
