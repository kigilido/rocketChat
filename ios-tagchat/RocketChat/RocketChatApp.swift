//
//  RocketChatApp.swift
//  RocketChat
//
//  Created by Rork on May 29, 2026.
//

import SwiftUI
import SwiftData

@main
struct RocketChatApp: App {
    @State private var identity = IdentityStore()
    @State private var location = LocationService()
    @State private var audio = AudioService()
    @State private var auth = AuthService()
    @State private var drops = DropService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ScannedTag.self,
            Conversation.self,
            Message.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // The local cache is disposable — rebuild it rather than trapping if
            // an older store can't be migrated.
            print("ModelContainer failed, rebuilding local cache: \(error)")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppGate()
                .environment(identity)
                .environment(location)
                .environment(audio)
                .environment(auth)
                .environment(drops)
        }
        .modelContainer(sharedModelContainer)
    }
}

/// Chooses between the launch state, the sign-in flow and the app itself.
private struct AppGate: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            switch auth.phase {
            case .loading:
                LaunchView()
            case .signedOut, .awaitingCode:
                PhoneAuthView()
            case .signedIn:
                RootTabView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.isSignedIn)
    }
}

/// Brief branded state while the stored session is restored.
private struct LaunchView: View {
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Theme.accent.opacity(0.25), lineWidth: 2)
                        .frame(width: pulse ? 110 : 74, height: pulse ? 110 : 74)
                        .opacity(pulse ? 0 : 1)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(Theme.accentGradient)
                }
                Text("TagChat")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
