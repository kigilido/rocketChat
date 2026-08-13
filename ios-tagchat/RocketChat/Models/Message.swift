//
//  Message.swift
//  RocketChat
//

import Foundation
import SwiftData

/// A single message inside a `Conversation`.
@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var text: String
    /// True when authored by the local (anonymous) user.
    var isMine: Bool
    var senderHandle: String
    var timestamp: Date

    /// Comma-separated emoji reactions from the local user.
    var reactionsRaw: String?
    /// True for voice-note messages; `text` holds the duration label.
    var isVoiceMessage: Bool
    /// Filename of the audio file in the documents directory.
    var audioFileName: String?
    /// Duration of the voice note in seconds.
    var audioDuration: TimeInterval
    /// Storage object path for a synced voice note, if any.
    var audioRemotePath: String?
    /// Emoji reactions from everyone in the room, keyed by emoji.
    var remoteReactionsRaw: String?

    var conversation: Conversation?

    init(
        id: UUID = UUID(),
        text: String,
        isMine: Bool,
        senderHandle: String,
        timestamp: Date = .now,
        isVoiceMessage: Bool = false,
        audioFileName: String? = nil,
        audioDuration: TimeInterval = 0
    ) {
        self.id = id
        self.text = text
        self.isMine = isMine
        self.senderHandle = senderHandle
        self.timestamp = timestamp
        self.isVoiceMessage = isVoiceMessage
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
    }

    var reactions: [String] {
        get {
            guard let raw = reactionsRaw, !raw.isEmpty else { return [] }
            return raw.split(separator: ",").map(String.init)
        }
        set {
            reactionsRaw = newValue.isEmpty ? nil : newValue.joined(separator: ",")
        }
    }

    func toggleReaction(_ emoji: String) {
        var current = reactions
        if let index = current.firstIndex(of: emoji) {
            current.remove(at: index)
        } else {
            current.append(emoji)
        }
        reactions = current
    }

    var durationLabel: String {
        guard audioDuration > 0 else { return "0:00" }
        let minutes = Int(audioDuration) / 60
        let seconds = Int(audioDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
