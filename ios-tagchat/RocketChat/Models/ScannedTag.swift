//
//  ScannedTag.swift
//  RocketChat
//

import Foundation
import SwiftData
import CoreLocation

/// A real-world identifier (plate, QR, sign, …) the user scanned. Each scan is
/// geotagged so it can be surfaced on the map and turned into an anonymous chat.
@Model
final class ScannedTag {
    @Attribute(.unique) var id: UUID
    /// The raw decoded value. Never displayed in full to preserve privacy.
    var code: String
    var kindRaw: String
    /// Stable privacy-preserving key so repeat scans of the same identifier
    /// increment the activity counter instead of creating duplicates.
    var roomKey: String
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    var createdAt: Date
    /// How many times this tag has been scanned (activity feed).
    var scanCount: Int

    /// Conversation started from this tag, if any.
    @Relationship(deleteRule: .cascade) var conversation: Conversation?

    init(
        id: UUID = UUID(),
        code: String,
        kind: TagKind,
        latitude: Double? = nil,
        longitude: Double? = nil,
        placeName: String? = nil,
        createdAt: Date = .now,
        scanCount: Int = 1
    ) {
        self.id = id
        self.code = code
        self.kindRaw = kind.rawValue
        self.roomKey = TagPrivacy.roomKey(for: code, kind: kind)
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.createdAt = createdAt
        self.scanCount = scanCount
    }

    var kind: TagKind {
        get { TagKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// A privacy-preserving, anonymised label derived from the raw code.
    var maskedCode: String {
        TagPrivacy.mask(code, kind: kind)
    }

    /// Human-readable activity summary for the feed.
    var activityLabel: String {
        switch scanCount {
        case 1: return "First scan"
        case 2...5: return "\(scanCount) scans"
        default: return "\(scanCount)+ scans"
        }
    }
}
