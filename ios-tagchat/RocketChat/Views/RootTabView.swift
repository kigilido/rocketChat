//
//  RootTabView.swift
//  RocketChat
//

import SwiftUI

/// Top-level tab navigation: Chats, Scan, Drops, Map, Settings.
struct RootTabView: View {
    @State private var selectedTab: Tab = .scan
    /// Conversation to deep-link into after a scan or drop reply; consumed by the Chats tab.
    @State private var pendingConversation: Conversation?

    enum Tab: Hashable {
        case chats, scan, drops, map, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatListView(route: $pendingConversation)
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.chats)

            ScanView { conversation in
                pendingConversation = conversation
                selectedTab = .chats
            }
            .tabItem { Label("Scan", systemImage: "viewfinder") }
            .tag(Tab.scan)

            DropsView(route: $pendingConversation)
                .onChange(of: pendingConversation) { _, newValue in
                    if newValue != nil { selectedTab = .chats }
                }
                .tabItem { Label("Drops", systemImage: "mappin.and.ellipse") }
                .tag(Tab.drops)

            TagMapView(route: $pendingConversation)
                .onChange(of: pendingConversation) { _, newValue in
                    if newValue != nil { selectedTab = .chats }
                }
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(Tab.map)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}
