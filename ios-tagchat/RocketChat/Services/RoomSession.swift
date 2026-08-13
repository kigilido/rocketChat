//
//  RoomSession.swift
//  RocketChat
//
//  Bridges one conversation to its Supabase room. Supabase is the transport;
//  SwiftData stays the local cache so the chat list and offline reads keep
//  working exactly as before.
//

import Foundation
import SwiftData
import Supabase
import Realtime

@Observable
@MainActor
final class RoomSession {
    /// Contact-sharing state for the banner and nav-bar affordance.
    enum ContactState: Equatable {
        case none
        case outgoingPending
        case incomingPending(requestID: UUID, from: String)
        case accepted
        case declined
    }

    private(set) var roomID: UUID?
    private(set) var contactState: ContactState = .none
    private(set) var revealedContacts: [RevealedContact] = []
    private(set) var isConnecting: Bool = true
    private(set) var isOffline: Bool = false
    var errorMessage: String?

    private let conversation: Conversation
    private let context: ModelContext
    private let myUserID: UUID
    private let myUsername: String

    private var usernames: [UUID: String] = [:]
    private var channel: RealtimeChannelV2?
    private var listenerTasks: [Task<Void, Never>] = []

    init(conversation: Conversation, context: ModelContext, myUserID: UUID, myUsername: String) {
        self.conversation = conversation
        self.context = context
        self.myUserID = myUserID
        self.myUsername = myUsername
    }

    // MARK: - Lifecycle

    func start() async {
        isConnecting = true
        defer { isConnecting = false }

        do {
            let room = try await resolveRoom()
            roomID = room.id
            conversation.remoteRoomID = room.id.uuidString

            try await joinRoom(room.id)
            await loadUsernames(roomID: room.id)
            await refreshMessages()
            await refreshContactState()
            await subscribe(to: room.id)
            isOffline = false
        } catch {
            print("RoomSession.start failed: \(error)")
            isOffline = true
            errorMessage = "You're offline — messages will send once you reconnect."
        }
    }

    func stop() {
        listenerTasks.forEach { $0.cancel() }
        listenerTasks = []
        if let channel {
            Task { await channel.unsubscribe() }
        }
        channel = nil
    }

    /// Find the shared room for this conversation's key, or create it.
    private func resolveRoom() async throws -> Room {
        let key = conversation.roomKey ?? "local:\(conversation.id.uuidString)"

        let existing: [Room] = try await supabase
            .from("rooms")
            .select("id, room_key, kind, label, drop_id, created_at, expires_at")
            .eq("room_key", value: key)
            .limit(1)
            .execute()
            .value

        if let room = existing.first { return room }

        let expiresAt: Date? = conversation.ttlSeconds > 0
            ? conversation.createdAt.addingTimeInterval(TimeInterval(conversation.ttlSeconds))
            : nil

        do {
            return try await supabase
                .from("rooms")
                .insert(RoomInsert(
                    roomKey: key,
                    kind: conversation.kind == .text ? "drop" : "tag",
                    label: conversation.title,
                    dropId: nil,
                    createdBy: myUserID,
                    expiresAt: expiresAt
                ))
                .select("id, room_key, kind, label, drop_id, created_at, expires_at")
                .single()
                .execute()
                .value
        } catch {
            // Someone else created the room in the meantime — re-read it.
            let raced: [Room] = try await supabase
                .from("rooms")
                .select("id, room_key, kind, label, drop_id, created_at, expires_at")
                .eq("room_key", value: key)
                .limit(1)
                .execute()
                .value
            guard let room = raced.first else { throw error }
            return room
        }
    }

    private func joinRoom(_ id: UUID) async throws {
        try await supabase
            .from("room_members")
            .upsert(RoomMemberInsert(roomId: id, userId: myUserID))
            .execute()
    }

    // MARK: - Realtime

    private func subscribe(to id: UUID) async {
        let channel = supabase.channel("room:\(id.uuidString)")
        self.channel = channel

        let messageInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: "room_id=eq.\(id.uuidString)"
        )
        let messageUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "messages",
            filter: "room_id=eq.\(id.uuidString)"
        )
        let requestChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "contact_requests",
            filter: "room_id=eq.\(id.uuidString)"
        )

        await channel.subscribe()

        // Realtime only signals "something changed" — the authoritative read goes
        // back through PostgREST, which decodes timestamps correctly for us.
        listenerTasks.append(Task { [weak self] in
            for await _ in messageInserts {
                await self?.refreshMessages()
            }
        })
        listenerTasks.append(Task { [weak self] in
            for await _ in messageUpdates {
                await self?.refreshMessages()
            }
        })
        listenerTasks.append(Task { [weak self] in
            for await _ in requestChanges {
                await self?.refreshContactState()
            }
        })
    }

    // MARK: - Messages

    private func loadUsernames(roomID: UUID) async {
        struct MemberRow: Decodable, Sendable { let user_id: UUID }
        do {
            let members: [MemberRow] = try await supabase
                .from("room_members")
                .select("user_id")
                .eq("room_id", value: roomID)
                .execute()
                .value

            let ids = members.map(\.user_id)
            guard !ids.isEmpty else { return }

            let profiles: [Profile] = try await supabase
                .from("profiles")
                .select("id, username, phone_last4")
                .in("id", values: ids)
                .execute()
                .value

            for profile in profiles {
                usernames[profile.id] = profile.username
            }
        } catch {
            print("loadUsernames failed: \(error)")
        }
    }

    /// Pull the server's messages and mirror any new ones into SwiftData.
    func refreshMessages() async {
        guard let roomID else { return }

        do {
            let remote: [RemoteMessage] = try await supabase
                .from("messages")
                .select("id, room_id, sender_id, kind, body, audio_path, duration, reactions, created_at")
                .eq("room_id", value: roomID)
                .order("created_at", ascending: true)
                .execute()
                .value

            // Resolve any unfamiliar senders up front so bubbles never render
            // with a placeholder handle.
            let unknownSenders = remote.compactMap(\.senderId).filter { $0 != myUserID && usernames[$0] == nil }
            if !unknownSenders.isEmpty {
                await loadUsernames(roomID: roomID)
            }

            let knownIDs = Set(conversation.messages.map(\.id))

            for row in remote {
                if let existing = conversation.messages.first(where: { $0.id == row.id }) {
                    applyReactions(row, to: existing)
                    continue
                }
                guard !knownIDs.contains(row.id) else { continue }

                let message = Message(
                    id: row.id,
                    text: row.body ?? (row.isVoice ? "Voice note" : ""),
                    isMine: row.senderId == myUserID,
                    senderHandle: handle(for: row.senderId),
                    timestamp: row.createdAt ?? .now,
                    isVoiceMessage: row.isVoice,
                    audioFileName: nil,
                    audioDuration: row.duration ?? 0
                )
                message.audioRemotePath = row.audioPath
                applyReactions(row, to: message)
                message.conversation = conversation
                conversation.messages.append(message)
                context.insert(message)

                if row.isVoice, let path = row.audioPath {
                    Task { await self.downloadVoiceNote(path: path, into: message) }
                }
            }

            if let latest = remote.last?.createdAt, latest > conversation.lastActivityAt {
                conversation.lastActivityAt = latest
            }

            isOffline = false
        } catch {
            print("refreshMessages failed: \(error)")
            isOffline = true
        }
    }

    private func applyReactions(_ row: RemoteMessage, to message: Message) {
        let all = row.reactions.keys.sorted()
        message.remoteReactionsRaw = all.isEmpty ? nil : all.joined(separator: ",")
        message.reactions = all
    }

    private func handle(for userID: UUID?) -> String {
        guard let userID else { return "Someone" }
        if userID == myUserID { return myUsername }
        return usernames[userID] ?? "Someone"
    }

    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let id = UUID()
        let local = Message(
            id: id,
            text: trimmed,
            isMine: true,
            senderHandle: myUsername
        )
        local.conversation = conversation
        conversation.messages.append(local)
        conversation.lastActivityAt = .now
        context.insert(local)

        guard let roomID else { return }

        do {
            try await supabase
                .from("messages")
                .insert(MessageInsert(
                    id: id,
                    roomId: roomID,
                    senderId: myUserID,
                    kind: "text",
                    body: trimmed,
                    audioPath: nil,
                    duration: nil
                ))
                .execute()
        } catch {
            print("send failed: \(error)")
            errorMessage = "Message couldn't be delivered."
        }
    }

    func sendVoiceNote(url: URL, duration: TimeInterval) async {
        let id = UUID()
        let local = Message(
            id: id,
            text: "Voice note",
            isMine: true,
            senderHandle: myUsername,
            isVoiceMessage: true,
            audioFileName: url.lastPathComponent,
            audioDuration: duration
        )
        local.conversation = conversation
        conversation.messages.append(local)
        conversation.lastActivityAt = .now
        context.insert(local)

        guard let roomID else { return }
        let path = "\(roomID.uuidString)/\(id.uuidString).m4a"

        do {
            let data = try Data(contentsOf: url)
            try await supabase.storage
                .from("voice-notes")
                .upload(path, data: data, options: FileOptions(contentType: "audio/m4a"))

            local.audioRemotePath = path

            try await supabase
                .from("messages")
                .insert(MessageInsert(
                    id: id,
                    roomId: roomID,
                    senderId: myUserID,
                    kind: "voice",
                    body: nil,
                    audioPath: path,
                    duration: duration
                ))
                .execute()
        } catch {
            print("sendVoiceNote failed: \(error)")
            errorMessage = "Voice note couldn't be delivered."
        }
    }

    private func downloadVoiceNote(path: String, into message: Message) async {
        do {
            let data = try await supabase.storage.from("voice-notes").download(path: path)
            let fileName = "\(message.id.uuidString).m4a"
            let destination = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)
            try data.write(to: destination, options: .atomic)
            message.audioFileName = fileName
        } catch {
            print("downloadVoiceNote failed: \(error)")
        }
    }

    func toggleReaction(_ emoji: String, on message: Message) async {
        guard let roomID else { return }

        var current = Set(message.reactions)
        if current.contains(emoji) { current.remove(emoji) } else { current.insert(emoji) }
        let sorted = current.sorted()
        message.reactions = sorted

        var payload: [String: [String]] = [:]
        for key in sorted { payload[key] = [myUserID.uuidString] }

        do {
            try await supabase
                .from("messages")
                .update(MessageReactionsUpdate(reactions: payload))
                .eq("id", value: message.id)
                .eq("room_id", value: roomID)
                .execute()
        } catch {
            print("toggleReaction failed: \(error)")
        }
    }

    // MARK: - Contact requests

    func refreshContactState() async {
        guard let roomID else { return }

        do {
            let requests: [ContactRequest] = try await supabase
                .from("contact_requests")
                .select("id, room_id, requester_id, status, created_at")
                .eq("room_id", value: roomID)
                .order("created_at", ascending: false)
                .execute()
                .value

            if requests.contains(where: { $0.state == .accepted }) {
                contactState = .accepted
                await loadRevealedContacts()
                return
            }

            if let pending = requests.first(where: { $0.state == .pending }) {
                if pending.requesterId == myUserID {
                    contactState = .outgoingPending
                } else {
                    contactState = .incomingPending(
                        requestID: pending.id,
                        from: handle(for: pending.requesterId)
                    )
                }
                return
            }

            contactState = requests.contains(where: { $0.state == .declined }) ? .declined : .none
        } catch {
            print("refreshContactState failed: \(error)")
        }
    }

    func requestContact() async {
        guard let roomID else { return }
        do {
            try await supabase
                .from("contact_requests")
                .insert(ContactRequestInsert(roomId: roomID, requesterId: myUserID))
                .execute()
            contactState = .outgoingPending
        } catch {
            print("requestContact failed: \(error)")
            errorMessage = "Couldn't send the contact request."
        }
    }

    func resolveContactRequest(id: UUID, accept: Bool) async {
        do {
            try await supabase
                .from("contact_requests")
                .update(ContactRequestResolve(
                    status: accept ? "accepted" : "declined",
                    resolvedAt: Date()
                ))
                .eq("id", value: id)
                .execute()
            await refreshContactState()
        } catch {
            print("resolveContactRequest failed: \(error)")
            errorMessage = "Couldn't update the contact request."
        }
    }

    private func loadRevealedContacts() async {
        guard let roomID else { return }
        struct Params: Encodable, Sendable {
            let p_room_id: String
        }
        do {
            revealedContacts = try await supabase
                .rpc("get_room_contacts", params: Params(p_room_id: roomID.uuidString))
                .execute()
                .value
        } catch {
            print("loadRevealedContacts failed: \(error)")
        }
    }
}
