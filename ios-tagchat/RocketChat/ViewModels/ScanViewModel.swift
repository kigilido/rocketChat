//
//  ScanViewModel.swift
//  RocketChat
//

import Foundation
import SwiftData
import CoreLocation

/// Drives the Scan tab: tracks what the camera has detected and turns a
/// confirmed scan into a geotagged `ScannedTag` + anonymous `Conversation`.
@Observable
final class ScanViewModel {
    /// The most recently detected raw value from the camera/AR pipeline.
    var detectedValue: String?
    var detectedKind: TagKind = .qrCode
    /// Set after a successful capture so the UI can route into the new chat.
    var startedConversation: Conversation?
    var isPresentingResult: Bool = false

    func handleDetection(value: String, kind: TagKind) {
        detectedValue = value
        detectedKind = kind
        isPresentingResult = true
    }

    func reset() {
        detectedValue = nil
        isPresentingResult = false
        startedConversation = nil
    }

    /// Persist the scan and open (or reuse) an anonymous conversation for it.
    /// If the same tag was scanned before, increments the scan count for the
    /// activity feed and reuses the existing conversation.
    @discardableResult
    func commit(
        context: ModelContext,
        handle: String,
        location: CLLocation?,
        placeName: String?,
        ttl: ConversationTTL
    ) -> Conversation? {
        guard let value = detectedValue else { return nil }

        let roomKey = TagPrivacy.roomKey(for: value, kind: detectedKind)

        // Check if a tag with the same roomKey already exists
        let descriptor = FetchDescriptor<ScannedTag>(
            predicate: #Predicate { $0.roomKey == roomKey }
        )
        let existingTags = try? context.fetch(descriptor)
        let existingTag = existingTags?.first

        if let existingTag {
            // Increment scan count for the activity feed
            existingTag.scanCount += 1
            if let loc = location {
                existingTag.latitude = loc.coordinate.latitude
                existingTag.longitude = loc.coordinate.longitude
            }
            if let placeName { existingTag.placeName = placeName }

            // Reuse the existing conversation if one exists
            if let conversation = existingTag.conversation {
                // Backfill the shared key for conversations created before sync.
                if conversation.roomKey == nil { conversation.roomKey = roomKey }
                startedConversation = conversation
                return conversation
            }

            // Tag exists but no conversation yet — create one
            let conversation = Conversation(
                title: existingTag.maskedCode,
                kind: detectedKind,
                myHandle: handle,
                ttl: ttl,
                roomKey: roomKey
            )
            existingTag.conversation = conversation
            context.insert(conversation)
            startedConversation = conversation
            return conversation
        }

        // Brand new tag
        let tag = ScannedTag(
            code: value,
            kind: detectedKind,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            placeName: placeName
        )

        let conversation = Conversation(
            title: tag.maskedCode,
            kind: detectedKind,
            myHandle: handle,
            ttl: ttl,
            roomKey: roomKey
        )
        tag.conversation = conversation

        context.insert(tag)
        context.insert(conversation)

        startedConversation = conversation
        return conversation
    }
}
