//
//  DropService.swift
//  RocketChat
//
//  Loads, creates and replies to street drops.
//

import Foundation
import CoreLocation
import Supabase

@Observable
@MainActor
final class DropService {
    private(set) var drops: [Drop] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    /// Drops within the user's visibility radius of `origin`, freshest first.
    func visibleDrops(from origin: CLLocationCoordinate2D?, radius: DropRadius) -> [Drop] {
        let live = drops.filter { !$0.isExpired }

        guard let origin, let limit = radius.metres else {
            return live
        }

        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return live.filter { drop in
            let there = CLLocation(latitude: drop.lat, longitude: drop.lng)
            return here.distance(from: there) <= limit
        }
    }

    func distanceLabel(to drop: Drop, from origin: CLLocationCoordinate2D?) -> String? {
        guard let origin else { return nil }
        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let there = CLLocation(latitude: drop.lat, longitude: drop.lng)
        let metres = here.distance(from: there)
        if metres < 1_000 {
            return "\(Int(metres.rounded())) m away"
        }
        return String(format: "%.1f km away", metres / 1_000)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            drops = try await supabase
                .from("drops")
                .select("id, author_id, category, title, body, lat, lng, reply_count, created_at, expires_at")
                .order("created_at", ascending: false)
                .limit(300)
                .execute()
                .value
        } catch {
            print("DropService.load failed: \(error)")
            errorMessage = "Couldn't load nearby drops."
        }
    }

    @discardableResult
    func createDrop(
        authorID: UUID,
        category: DropCategory,
        title: String,
        body: String?,
        coordinate: CLLocationCoordinate2D,
        ttl: ConversationTTL
    ) async -> Drop? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresAt: Date? = ttl.rawValue > 0
            ? Date().addingTimeInterval(TimeInterval(ttl.rawValue))
            : nil

        do {
            let created: Drop = try await supabase
                .from("drops")
                .insert(DropInsert(
                    authorId: authorID,
                    category: category.rawValue,
                    title: trimmedTitle,
                    body: (trimmedBody?.isEmpty ?? true) ? nil : trimmedBody,
                    lat: coordinate.latitude,
                    lng: coordinate.longitude,
                    expiresAt: expiresAt
                ))
                .select("id, author_id, category, title, body, lat, lng, reply_count, created_at, expires_at")
                .single()
                .execute()
                .value

            drops.insert(created, at: 0)
            return created
        } catch {
            print("createDrop failed: \(error)")
            errorMessage = "Couldn't publish your drop."
            return nil
        }
    }

    func deleteDrop(_ drop: Drop) async {
        do {
            try await supabase.from("drops").delete().eq("id", value: drop.id).execute()
            drops.removeAll { $0.id == drop.id }
        } catch {
            print("deleteDrop failed: \(error)")
            errorMessage = "Couldn't remove that drop."
        }
    }

    /// Open (or reuse) the confidential thread for a drop and return the room key
    /// the local conversation should bind to.
    ///
    /// A replier can't add the drop author to a room under RLS, so thread setup
    /// goes through the `open_drop_thread` routine which wires up both sides.
    /// The author instead opens the most recent thread someone started with them.
    func openReplyThread(drop: Drop, userID: UUID) async -> String? {
        if drop.authorId == userID {
            return await newestAuthorThread(for: drop)
        }

        nonisolated struct Params: Encodable, Sendable {
            let p_drop_id: String
        }

        do {
            _ = try await supabase
                .rpc("open_drop_thread", params: Params(p_drop_id: drop.id.uuidString))
                .execute()

            if let index = drops.firstIndex(where: { $0.id == drop.id }) {
                let current = drops[index]
                if current.replyCount == drop.replyCount {
                    await load()
                }
            }

            return "drop:\(drop.id.uuidString):\(userID.uuidString)"
        } catch {
            print("openReplyThread failed: \(error)")
            errorMessage = "Couldn't open that conversation."
            return nil
        }
    }

    /// The freshest thread a replier started on the author's own drop.
    private func newestAuthorThread(for drop: Drop) async -> String? {
        do {
            let rooms: [Room] = try await supabase
                .from("rooms")
                .select("id, room_key, kind, label, drop_id, created_at, expires_at")
                .eq("drop_id", value: drop.id)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            guard let room = rooms.first else {
                errorMessage = "Nobody has replied to this drop yet."
                return nil
            }
            return room.roomKey
        } catch {
            print("newestAuthorThread failed: \(error)")
            errorMessage = "Couldn't open that conversation."
            return nil
        }
    }
}
