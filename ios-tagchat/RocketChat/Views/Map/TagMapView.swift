//
//  TagMapView.swift
//  RocketChat
//

import SwiftUI
import SwiftData
import MapKit

/// The Map tab. Plots every geotagged scan and lets the user jump into the
/// conversation attached to a tag. Shows scan activity counts.
struct TagMapView: View {
    /// What the map is currently plotting.
    private enum MapFilter: String, CaseIterable, Identifiable {
        case all, plates, drops

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .plates: return "Plates"
            case .drops: return "Drops"
            }
        }
    }

    @Environment(LocationService.self) private var location
    @Environment(DropService.self) private var dropService
    @Environment(IdentityStore.self) private var identity
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScannedTag.createdAt, order: .reverse)
    private var tags: [ScannedTag]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedTag: ScannedTag?
    @State private var selectedDrop: Drop?
    @State private var filter: MapFilter = .all
    @State private var isOpeningThread: Bool = false

    /// Conversation the user chose to open from a tag callout.
    @Binding var route: Conversation?

    private var geotaggedTags: [ScannedTag] {
        guard filter != .drops else { return [] }
        return tags.filter { $0.coordinate != nil }
    }

    private var visibleDrops: [Drop] {
        guard filter != .plates else { return [] }
        return dropService.visibleDrops(
            from: location.lastLocation?.coordinate,
            radius: identity.dropRadius
        )
    }

    private var isEmpty: Bool {
        geotaggedTags.isEmpty && visibleDrops.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                map

                VStack(spacing: 0) {
                    filterBar
                    Spacer()
                    if isEmpty {
                        EmptyMapState(filter: filter.title)
                            .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $selectedTag) { tag in
                TagDetailSheet(tag: tag) {
                    if let conversation = tag.conversation {
                        selectedTag = nil
                        route = conversation
                    }
                }
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedDrop) { drop in
                DropDetailSheet(
                    drop: drop,
                    distance: dropService.distanceLabel(to: drop, from: location.lastLocation?.coordinate),
                    isBusy: isOpeningThread,
                    onReply: { openThread(for: drop) }
                )
                .presentationDetents([.height(400)])
                .presentationDragIndicator(.visible)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            location.refresh()
            await dropService.load()
        }
    }

    private var filterBar: some View {
        Picker("Show", selection: $filter) {
            ForEach(MapFilter.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    /// Open (or reuse) the confidential thread for a drop and route into it.
    private func openThread(for drop: Drop) {
        guard let userID = auth.userID else { return }
        isOpeningThread = true

        Task {
            defer { isOpeningThread = false }
            guard let roomKey = await dropService.openReplyThread(drop: drop, userID: userID) else { return }

            let conversation = ConversationStore.conversation(
                forRoomKey: roomKey,
                title: drop.title,
                kind: .text,
                myHandle: auth.profile?.username ?? identity.handle,
                ttl: identity.defaultTTL,
                context: modelContext
            )
            selectedDrop = nil
            route = conversation
        }
    }

    private var map: some View {
        Map(position: $cameraPosition, selection: $selectedTag) {
            UserAnnotation()

            ForEach(geotaggedTags) { tag in
                if let coordinate = tag.coordinate {
                    Marker(tag.maskedCode, systemImage: tag.kind.systemImage, coordinate: coordinate)
                        .tint(tag.kind.tint)
                        .tag(tag)
                }
            }

            ForEach(visibleDrops) { drop in
                Annotation(
                    drop.title,
                    coordinate: CLLocationCoordinate2D(latitude: drop.lat, longitude: drop.lng)
                ) {
                    Button {
                        selectedDrop = drop
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Theme.background.opacity(0.85))
                                .frame(width: 38, height: 38)
                            Circle()
                                .strokeBorder(drop.dropCategory.tint, lineWidth: 2)
                                .frame(width: 38, height: 38)
                            Image(systemName: drop.dropCategory.systemImage)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(drop.dropCategory.tint)
                        }
                        .opacity(drop.isExpired ? 0.35 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct TagDetailSheet: View {
    let tag: ScannedTag
    var onOpenChat: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tag.kind.tint.opacity(0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: tag.kind.systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(tag.kind.tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(tag.maskedCode)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(tag.placeName ?? tag.kind.title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            // Activity feed
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                Text(tag.activityLabel)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("Scanned \(tag.createdAt, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(tag.scanCount > 1 ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                tag.scanCount > 1 ? Theme.accentSoft : Theme.surfaceElevated,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            Button(action: onOpenChat) {
                Label("Open Anonymous Chat", systemImage: "bubble.left.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }
}

private struct EmptyMapState: View {
    let filter: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Nothing to show here")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Geotagged scans and nearby street drops appear on this map.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}
