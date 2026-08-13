//
//  AuthService.swift
//  RocketChat
//
//  Phone + one-time-passcode sign in, backed by two edge functions that mint a
//  real Supabase session once the code checks out.
//

import Foundation
import Supabase

nonisolated private struct RequestOTPBody: Encodable, Sendable {
    let phone: String
}

nonisolated private struct RequestOTPResponse: Codable, Sendable {
    let sent: Bool?
    let delivered: Bool?
    let devCode: String?
    let error: String?
}

nonisolated private struct VerifyOTPBody: Encodable, Sendable {
    let phone: String
    let code: String
}

nonisolated private struct VerifyOTPResponse: Codable, Sendable {
    let tokenHash: String?
    let isNewUser: Bool?
    let error: String?
}

/// Where the user is in the sign-in journey.
enum AuthPhase: Equatable {
    case loading
    case signedOut
    case awaitingCode(phone: String)
    case signedIn
}

@Observable
@MainActor
final class AuthService {
    private(set) var phase: AuthPhase = .loading
    private(set) var profile: Profile?
    private(set) var handles: ContactHandles = .empty
    private(set) var isBusy: Bool = false
    var errorMessage: String?
    /// Surfaced only when no SMS provider is configured, so the flow stays testable.
    private(set) var devCode: String?

    private var authStateTask: Task<Void, Never>?

    var userID: UUID? { profile?.id }
    var isSignedIn: Bool { phase == .signedIn }

    init() {
        observeAuthChanges()
    }

    private func observeAuthChanges() {
        authStateTask = Task { [weak self] in
            for await state in supabase.auth.authStateChanges {
                guard let self else { return }
                switch state.event {
                case .signedIn, .initialSession, .tokenRefreshed, .userUpdated:
                    if state.session != nil {
                        await self.loadProfile()
                    } else if state.event == .initialSession {
                        self.phase = .signedOut
                    }
                case .signedOut:
                    self.profile = nil
                    self.handles = .empty
                    self.phase = .signedOut
                default:
                    break
                }
            }
        }
    }

    // MARK: - Sign in

    /// Ask the backend to send a passcode to `phone`.
    func requestCode(phone: String) async {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard trimmed.filter(\.isNumber).count >= 7 else {
            errorMessage = "Enter a valid phone number."
            return
        }

        isBusy = true
        errorMessage = nil
        devCode = nil
        defer { isBusy = false }

        do {
            let response: RequestOTPResponse = try await supabase.functions.invoke(
                "request-otp",
                options: .init(body: RequestOTPBody(phone: trimmed))
            )
            if let error = response.error {
                errorMessage = error
                return
            }
            devCode = response.devCode
            phase = .awaitingCode(phone: trimmed)
        } catch {
            print("requestCode failed: \(error)")
            errorMessage = "Couldn't send your code. Check your connection and try again."
        }
    }

    /// Verify the passcode and exchange it for a Supabase session.
    func verifyCode(_ code: String) async {
        guard case let .awaitingCode(phone) = phase else { return }

        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else {
            errorMessage = "Enter all six digits."
            return
        }

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let response: VerifyOTPResponse = try await supabase.functions.invoke(
                "verify-otp",
                options: .init(body: VerifyOTPBody(phone: phone, code: digits))
            )

            if let error = response.error {
                errorMessage = error
                return
            }

            guard let tokenHash = response.tokenHash else {
                errorMessage = "Couldn't complete sign in. Try again."
                return
            }

            try await supabase.auth.verifyOTP(tokenHash: tokenHash, type: .magiclink)
            devCode = nil
            await loadProfile()
        } catch {
            print("verifyCode failed: \(error)")
            errorMessage = "Couldn't complete sign in. Try again."
        }
    }

    /// Step back to the phone entry screen.
    func restartSignIn() {
        phase = .signedOut
        errorMessage = nil
        devCode = nil
    }

    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            print("signOut failed: \(error)")
        }
        profile = nil
        handles = .empty
        phase = .signedOut
    }

    // MARK: - Profile

    /// Load (and wait for) the profile row the signup trigger creates.
    func loadProfile() async {
        guard let user = supabase.auth.currentUser else {
            phase = .signedOut
            return
        }

        // The row is created by a trigger, so retry briefly on a cold signup.
        for attempt in 0..<4 {
            do {
                let loaded: Profile = try await supabase
                    .from("profiles")
                    .select("id, username, phone_last4")
                    .eq("id", value: user.id)
                    .single()
                    .execute()
                    .value
                profile = loaded
                phase = .signedIn
                await loadHandles()
                return
            } catch {
                if attempt == 3 {
                    print("loadProfile failed: \(error)")
                    errorMessage = "Couldn't load your profile."
                    phase = .signedOut
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    /// Generate a fresh anonymous username server-side.
    func rerollUsername() async {
        guard let id = profile?.id else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let updated: Profile = try await supabase
                .from("profiles")
                .update(ProfileUsernameUpdate(username: Self.randomUsername()))
                .eq("id", value: id)
                .select("id, username, phone_last4")
                .single()
                .execute()
                .value
            profile = updated
        } catch {
            print("rerollUsername failed: \(error)")
            errorMessage = "That handle was taken. Try again."
        }
    }

    // MARK: - Contact handles

    func loadHandles() async {
        guard let id = profile?.id else { return }
        do {
            let rows: [ContactHandles] = try await supabase
                .from("contact_handles")
                .select("instagram, whatsapp, telegram, other")
                .eq("user_id", value: id)
                .execute()
                .value
            handles = rows.first ?? .empty
        } catch {
            print("loadHandles failed: \(error)")
        }
    }

    func saveHandles(_ new: ContactHandles) async {
        guard let id = profile?.id else { return }
        isBusy = true
        defer { isBusy = false }

        func clean(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        do {
            try await supabase
                .from("contact_handles")
                .upsert(ContactHandlesUpsert(
                    userId: id,
                    instagram: clean(new.instagram),
                    whatsapp: clean(new.whatsapp),
                    telegram: clean(new.telegram),
                    other: clean(new.other)
                ))
                .execute()
            handles = new
        } catch {
            print("saveHandles failed: \(error)")
            errorMessage = "Couldn't save your handles."
        }
    }

    // MARK: - Helpers

    private static let adjectives = [
        "Crimson", "Silent", "Neon", "Velvet", "Hidden", "Electric",
        "Lunar", "Amber", "Static", "Cobalt", "Quiet", "Phantom",
        "Rogue", "Drift", "Midnight", "Solar"
    ]
    private static let animals = [
        "Fox", "Heron", "Lynx", "Moth", "Otter", "Raven",
        "Wolf", "Koi", "Falcon", "Mantis", "Stag", "Orca",
        "Ibis", "Viper", "Crane", "Jackal"
    ]

    private static func randomUsername() -> String {
        let adjective = adjectives.randomElement() ?? "Quiet"
        let animal = animals.randomElement() ?? "Fox"
        return "\(adjective) \(animal) \(Int.random(in: 100...999))"
    }
}
