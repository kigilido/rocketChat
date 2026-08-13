//
//  SettingsView.swift
//  RocketChat
//

import SwiftUI
import SwiftData
import CoreLocation

/// The Settings tab. Manage the anonymous identity, privacy controls, voice
/// masking, ephemeral defaults, and data.
struct SettingsView: View {
    @Environment(IdentityStore.self) private var identity
    @Environment(LocationService.self) private var location
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @Query private var conversations: [Conversation]
    @Query private var tags: [ScannedTag]

    @State private var showResetConfirm = false
    @State private var showSignOutConfirm = false
    @State private var isEditingHandles = false

    var body: some View {
        @Bindable var identity = identity

        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                List {
                    accountSection
                    contactHandlesSection
                    privacySection(identity: $identity.ghostMode)
                    dropRadiusSection(radius: $identity.dropRadius)
                    voiceSection(identity: $identity.voiceMaskingEnabled)
                    ephemeralSection(identity: $identity.defaultTTL)
                    locationSection
                    dataSection
                    aboutSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $isEditingHandles) {
                ContactHandlesEditor()
            }
            .confirmationDialog("Clear all chats and scans?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive, action: clearData)
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Sign out of TagChat?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to verify your phone number again to get back in.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.accentSoft)
                        .frame(width: 54, height: 54)
                    Image(systemName: "theatermasks.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.profile?.username ?? identity.handle)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your anonymous handle")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .listRowBackground(Theme.surface)

            if let last4 = auth.profile?.phoneLast4, !last4.isEmpty {
                HStack {
                    Label("Phone", systemImage: "phone.fill")
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("••• ••• \(last4)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surface)
            }

            Button {
                identity.reroll()
                Task { await auth.rerollUsername() }
            } label: {
                Label("Generate New Handle", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.accent)
            }
            .disabled(auth.isBusy)
            .listRowBackground(Theme.surface)

            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .listRowBackground(Theme.surface)
        } header: {
            Text("Account")
        } footer: {
            Text("Your phone number verifies you're a real person. It is never shown to anyone you chat with.")
        }
    }

    private var contactHandlesSection: some View {
        Section {
            Button {
                isEditingHandles = true
            } label: {
                HStack {
                    Label("Social Handles", systemImage: "at")
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(auth.handles.isEmpty ? "Not set" : "Saved")
                        .font(.subheadline)
                        .foregroundStyle(auth.handles.isEmpty ? Theme.textTertiary : Theme.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            Text("Contact Sharing")
        } footer: {
            Text("These stay hidden until you and someone else both accept a contact request.")
        }
    }

    private func dropRadiusSection(radius: Binding<DropRadius>) -> some View {
        Section {
            Picker("Visibility radius", selection: radius) {
                ForEach(DropRadius.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .listRowBackground(Theme.surface)
        } header: {
            Text("Street Drops")
        } footer: {
            Text(radius.wrappedValue.subtitle + ". Drops beyond this distance are hidden from the Drops and Map tabs.")
        }
    }

    private func privacySection(identity ghostMode: Binding<Bool>) -> some View {
        Section {
            Toggle(isOn: ghostMode) {
                Label("Ghost Mode", systemImage: "eye.slash.fill")
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .listRowBackground(Theme.surface)
        } header: {
            Text("Privacy")
        } footer: {
            Text("In Ghost Mode your scans are not added to the public map.")
        }
    }

    private func voiceSection(identity voiceMasking: Binding<Bool>) -> some View {
        Section {
            Toggle(isOn: voiceMasking) {
                Label("Voice Masking", systemImage: "waveform.badge.filter")
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .listRowBackground(Theme.surface)
        } header: {
            Text("Voice Notes")
        } footer: {
            Text("When enabled, your voice is pitch-shifted in real time so it can't be recognised.")
        }
    }

    private func ephemeralSection(identity defaultTTL: Binding<ConversationTTL>) -> some View {
        Section {
            Picker("Default lifespan", selection: defaultTTL) {
                ForEach(ConversationTTL.allCases) { option in
                    Label(option.descriptiveLabel, systemImage: option.systemImage)
                        .tag(option)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .listRowBackground(Theme.surface)
        } header: {
            Text("Ephemeral Chats")
        } footer: {
            Text("New chats will auto-delete after this duration unless you change it during scan.")
        }
    }

    private var locationSection: some View {
        Section {
            HStack {
                Label("Location Access", systemImage: "location.fill")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(locationStatusText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surface)

            if !location.isAuthorized {
                Button {
                    location.requestPermission()
                } label: {
                    Label("Enable Location", systemImage: "location.circle")
                        .foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.surface)
            }
        } header: {
            Text("Location")
        } footer: {
            Text("Location is used to geotag your scans so they appear on the map.")
        }
    }

    private var dataSection: some View {
        Section {
            HStack {
                Text("Chats")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(conversations.count)")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surface)

            HStack {
                Text("Scanned Tags")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(tags.count)")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surface)

            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Clear All Data", systemImage: "trash.fill")
            }
            .listRowBackground(Theme.surface)
        } header: {
            Text("Data")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("1.1.0")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surface)
        } header: {
            Text("About")
        }
    }

    private var locationStatusText: String {
        switch location.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "Enabled"
        case .denied, .restricted: return "Denied"
        default: return "Not Set"
        }
    }

    private func clearData() {
        for conversation in conversations { modelContext.delete(conversation) }
        for tag in tags { modelContext.delete(tag) }
    }
}
