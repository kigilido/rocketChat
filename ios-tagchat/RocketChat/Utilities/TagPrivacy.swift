//
//  TagPrivacy.swift
//  RocketChat
//

import Foundation
import CryptoKit

/// Helpers that turn raw scanned values into privacy-preserving labels.
///
/// RocketChat never exposes the full decoded identifier in the UI — only a masked
/// hint is shown so two people who scanned the same thing recognise it, while a
/// casual observer cannot read someone's full plate or link.
enum TagPrivacy {
    /// Produce a short, partly-redacted label for a scanned value.
    static func mask(_ raw: String, kind: TagKind) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }

        switch kind {
        case .licensePlate:
            let cleaned = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
            let tail = String(cleaned.suffix(3))
            return "Plate ••• \(tail)"
        case .qrCode:
            let host = URL(string: trimmed)?.host ?? "code"
            return "QR · \(host)"
        case .sign:
            let words = trimmed.split(separator: " ").prefix(2).joined(separator: " ")
            return words.isEmpty ? "Sign" : "Sign · \(words)"
        case .text:
            let snippet = trimmed.prefix(12)
            return String(snippet)
        }
    }

    /// A stable, anonymised room key for a scanned value so two scans of the
    /// same identifier resolve to the same conversation — on any device.
    ///
    /// This must be a *stable* digest rather than `hashValue`: Swift seeds string
    /// hashing randomly per process, so two phones scanning the same plate would
    /// otherwise never land in the same room.
    static func roomKey(for raw: String, kind: TagKind) -> String {
        let normalised = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace }
        let digest = SHA256.hash(data: Data("\(kind.rawValue):\(normalised)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(kind.rawValue):\(hex.prefix(32))"
    }
}
