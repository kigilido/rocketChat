//
//  DropsView.swift
//  RocketChat
//
//  The Drops tab: a dark map of nearby street drops plus a create button.
//

import SwiftUI
import SwiftData
import MapKit

struct DropsView: View {
    @Environment(LocationService.self) private var location
    @Environment(DropService.self) private var drops
    @Environment(AuthService.self) private var auth
    @Environment(IdentityStore.self) private var identity
    @Environment(\.modelContext) private var modelContext

    @Binding var route: Conversation?

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedDrop: Drop?
    @State private var isCreating: Bool = false
    @State private var categoryFilter: DropCategory?
    @State private var isOpeningThread: Bool = false

    private var origin: CLLocationCoordinate2D? {
        location.lastLocation?.coordinate
    }

    private var visible: [Drop] {
        let nearby = drops.visibleDrops(from: origin, radius: identity.dropRadius)
        guard let categoryFilter else { return nearby }
        return nearby.filter { $0.dropCategory == categoryFilter }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                map
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    categoryChips
                    Spacer()
                    bottomBar
                }
            }
            .navigationTitle("Drops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Create a drop")
                }
            }
            .sheet(isPresented: $isCreating) {
                CreateDropSheet()
            }
            .sheet(item: $selectedDrop) { drop in
                DropDetailSheet(
                    drop: drop,
                    distance: drops.distanceLabel(to: drop, from: origin),
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
            await drops.load()
        }
        .refreshable { await drops.load() }
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            ForEach(visible) { drop in
                Annotation(
                    drop.title,
                    coordinate: CLLocationCoordinate2D(latitude: drop.lat, longitude: drop.lng)
                ) {
                    DropPin(drop: drop) { selectedDrop = drop }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", tint: Theme.accent, isOn: categoryFilter == nil) {
                    withAnimation(.spring(duration: 0.3)) { categoryFilter = nil }
                }
                ForEach(DropCategory.allCases) { category in
                    FilterChip(
                        title: category.title,
                        systemImage: category.systemImage,
                        tint: category.tint,
                        isOn: categoryFilter == category
                    ) {
                        withAnimation(.spring(duration: 0.3)) {
                            categoryFilter = categoryFilter == category ? nil : category
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if visible.isEmpty {
                EmptyDropsHint(radius: identity.dropRadius)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(visible) { drop in
                            DropCard(
                                drop: drop,
                                distance: drops.distanceLabel(to: drop, from: origin)
                            ) {
                                selectedDrop = drop
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 118)
            }
        }
        .padding(.bottom, 12)
    }

    /// Open (or reuse) the confidential thread for this drop and route into it.
    private func openThread(for drop: Drop) {
        guard let userID = auth.userID else { return }
        isOpeningThread = true

        Task {
            defer { isOpeningThread = false }
            guard let roomKey = await drops.openReplyThread(drop: drop, userID: userID) else { return }

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
}

// MARK: - Pin

private struct DropPin: View {
    let drop: Drop
    let onTap: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(drop.dropCategory.tint.opacity(0.22))
                        .frame(width: 42, height: 42)
                    Circle()
                        .strokeBorder(drop.dropCategory.tint, lineWidth: 2)
                        .frame(width: 42, height: 42)
                    Image(systemName: drop.dropCategory.systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(drop.dropCategory.tint)
                }

                if drop.replyCount > 0 {
                    Text("\(drop.replyCount)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Theme.accent, in: Circle())
                        .offset(x: 4, y: -3)
                }
            }
            .background(Circle().fill(Theme.background.opacity(0.85)).frame(width: 42, height: 42))
            .scaleEffect(appeared ? 1 : 0.4)
            .opacity(drop.isExpired ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

// MARK: - Cards & chips

private struct DropCard: View {
    let drop: Drop
    let distance: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: drop.dropCategory.systemImage)
                        .font(.system(size: 11, weight: .bold))
                    Text(drop.dropCategory.title.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                }
                .foregroundStyle(drop.dropCategory.tint)

                Text(drop.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let distance {
                        Label(distance, systemImage: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if drop.replyCount > 0 {
                        Label("\(drop.replyCount)", systemImage: "bubble.left.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(12)
            .frame(width: 210, height: 108, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(drop.dropCategory.tint.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct FilterChip: View {
    let title: String
    var systemImage: String?
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isOn ? .black : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.surfaceElevated), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyDropsHint: View {
    let radius: DropRadius

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Nothing dropped nearby")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Showing \(radius.title). Tap + to leave the first one.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 32)
    }
}
