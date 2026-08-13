//
//  ScanResultSheet.swift
//  RocketChat
//

import SwiftUI
import SwiftData

/// Confirmation sheet shown after a successful scan. Shows only the masked,
/// privacy-preserving label and lets the user start an anonymous chat.
/// Includes the tag activity feed and an ephemeral TTL picker.
struct ScanResultSheet: View {
    @Bindable var viewModel: ScanViewModel
    var onStart: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var ttl: ConversationTTL = .day
    @State private var scanCount: Int = 1

    private var maskedLabel: String {
        guard let value = viewModel.detectedValue else { return "Unknown" }
        return TagPrivacy.mask(value, kind: viewModel.detectedKind)
    }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(viewModel.detectedKind.tint.opacity(0.18))
                    .frame(width: 72, height: 72)
                Image(systemName: viewModel.detectedKind.systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(viewModel.detectedKind.tint)
            }
            .padding(.top, 4)

            VStack(spacing: 5) {
                Text(maskedLabel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(viewModel.detectedKind.title) detected")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Tag activity feed indicator
            TagActivityBadge(scanCount: scanCount, kind: viewModel.detectedKind)

            // Ephemeral TTL picker
            VStack(spacing: 8) {
                Label("Chat lifespan", systemImage: "timer")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Picker("Lifespan", selection: $ttl) {
                    ForEach(ConversationTTL.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Label("Your identity stays anonymous", systemImage: "eye.slash.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.cyan)

            Button(action: {
                onStart()
                dismiss()
            }) {
                Text("Start Anonymous Chat")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Button("Cancel") {
                viewModel.reset()
                dismiss()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .onAppear { checkExistingScans() }
    }

    private func checkExistingScans() {
        guard let value = viewModel.detectedValue else { return }
        let roomKey = TagPrivacy.roomKey(for: value, kind: viewModel.detectedKind)
        let descriptor = FetchDescriptor<ScannedTag>(
            predicate: #Predicate { $0.roomKey == roomKey }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            scanCount = existing.scanCount + 1
        }
    }
}

/// Shows how many times this tag has been scanned — the activity feed.
private struct TagActivityBadge: View {
    let scanCount: Int
    let kind: TagKind

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption)
            if scanCount > 1 {
                Text("\(scanCount) scans — tag is active")
                    .font(.caption.weight(.medium))
            } else {
                Text("First scan of this tag")
                    .font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(scanCount > 1 ? Theme.accent : Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            (scanCount > 1 ? Theme.accentSoft : Theme.surfaceElevated),
            in: Capsule()
        )
    }
}
