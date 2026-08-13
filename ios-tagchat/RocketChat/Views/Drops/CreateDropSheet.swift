//
//  CreateDropSheet.swift
//  RocketChat
//

import SwiftUI
import CoreLocation

struct CreateDropSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @Environment(DropService.self) private var drops
    @Environment(AuthService.self) private var auth

    @State private var category: DropCategory = .question
    @State private var title: String = ""
    @State private var detail: String = ""
    @State private var ttl: ConversationTTL = .day
    @State private var isSaving: Bool = false
    @State private var placeName: String?
    @FocusState private var titleFocused: Bool

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && location.lastLocation != nil
            && auth.userID != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        categoryPicker
                        titleField
                        detailField
                        lifespanPicker
                        locationRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 90)
                }

                VStack {
                    Spacer()
                    PrimaryActionButton(
                        title: "Drop it here",
                        isBusy: isSaving,
                        isEnabled: canPublish,
                        action: publish
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .background(
                        LinearGradient(colors: [.clear, Theme.background], startPoint: .top, endPoint: .bottom)
                            .frame(height: 120)
                            .allowsHitTesting(false),
                        alignment: .bottom
                    )
                }
            }
            .navigationTitle("New Drop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            location.refresh()
            titleFocused = true
            if let fix = location.lastLocation {
                placeName = await location.placeName(for: fix)
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("What kind of drop?")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(DropCategory.allCases) { option in
                    Button {
                        withAnimation(.spring(duration: 0.3)) { category = option }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: option.systemImage)
                                .font(.system(size: 15, weight: .semibold))
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(category == option ? .black : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(
                            category == option
                                ? AnyShapeStyle(option.tint)
                                : AnyShapeStyle(Theme.surfaceElevated),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Your \(category.title.lowercased())")

            TextField(
                "",
                text: $title,
                prompt: Text(category.placeholder).foregroundStyle(Theme.textTertiary),
                axis: .vertical
            )
            .focused($titleFocused)
            .font(.body)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1...3)
            .padding(14)
            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var detailField: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Add detail (optional)")

            TextField(
                "",
                text: $detail,
                prompt: Text("Anything else people should know").foregroundStyle(Theme.textTertiary),
                axis: .vertical
            )
            .font(.subheadline)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(2...5)
            .padding(14)
            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var lifespanPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("How long should it live?")

            HStack(spacing: 8) {
                ForEach(ConversationTTL.allCases) { option in
                    Button {
                        withAnimation(.spring(duration: 0.25)) { ttl = option }
                    } label: {
                        Text(option.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ttl == option ? .black : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                ttl == option
                                    ? AnyShapeStyle(Theme.accentGradient)
                                    : AnyShapeStyle(Theme.surfaceElevated),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var locationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: location.lastLocation == nil ? "location.slash.fill" : "location.fill")
                .font(.system(size: 14))
                .foregroundStyle(location.lastLocation == nil ? Theme.danger : Theme.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text(location.lastLocation == nil ? "Waiting for your location" : (placeName ?? "Current location"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(location.lastLocation == nil
                     ? "Drops are pinned where you stand."
                     : "Your drop pins here — never your exact address.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            if location.lastLocation == nil {
                Button("Enable") { location.requestPermission() }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func publish() {
        guard let userID = auth.userID, let fix = location.lastLocation else { return }
        isSaving = true

        Task {
            defer { isSaving = false }
            let created = await drops.createDrop(
                authorID: userID,
                category: category,
                title: title,
                body: detail,
                coordinate: fix.coordinate,
                ttl: ttl
            )
            if created != nil { dismiss() }
        }
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(Theme.textTertiary)
    }
}
