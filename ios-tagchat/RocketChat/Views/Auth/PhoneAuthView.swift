//
//  PhoneAuthView.swift
//  RocketChat
//
//  Phone number → 6-digit passcode → anonymous account.
//

import SwiftUI

struct PhoneAuthView: View {
    @Environment(AuthService.self) private var auth

    @State private var phone: String = ""
    @State private var code: String = ""
    @FocusState private var phoneFocused: Bool
    @FocusState private var codeFocused: Bool

    private var awaitingCode: Bool {
        if case .awaitingCode = auth.phase { return true }
        return false
    }

    private var codeDestination: String {
        if case let .awaitingCode(phone) = auth.phase { return phone }
        return ""
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScannerBackdrop()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                header

                if awaitingCode {
                    codeEntry
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    phoneEntry
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }

                Spacer(minLength: 0)

                footer
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
        .animation(.spring(duration: 0.4), value: awaitingCode)
        .onAppear { phoneFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accentSoft)
                    .frame(width: 78, height: 78)
                Image(systemName: awaitingCode ? "lock.shield.fill" : "viewfinder")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.accentGradient)
                    .contentTransition(.symbolEffect(.replace))
            }

            Text(awaitingCode ? "Enter your code" : "Welcome to TagChat")
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)

            Text(awaitingCode
                 ? "We sent a 6-digit code to \(codeDestination)."
                 : "Your number verifies you're real. Nobody ever sees it — you chat under an anonymous handle.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 34)
    }

    // MARK: - Phone entry

    private var phoneEntry: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textTertiary)

                TextField("", text: $phone, prompt: Text("+1 555 000 1234").foregroundStyle(Theme.textTertiary))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($phoneFocused)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(phoneFocused ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5)
            )

            errorLabel

            PrimaryActionButton(
                title: "Send code",
                isBusy: auth.isBusy,
                isEnabled: phone.filter(\.isNumber).count >= 7
            ) {
                Task { await auth.requestCode(phone: phone) }
            }
        }
    }

    // MARK: - Code entry

    private var codeEntry: some View {
        VStack(spacing: 16) {
            ZStack {
                // Hidden field drives the segmented display below.
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .opacity(0.02)
                    .onChange(of: code) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(6))
                        if digits != newValue { code = digits }
                        if digits.count == 6 {
                            Task { await auth.verifyCode(digits) }
                        }
                    }

                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { index in
                        CodeSlot(
                            digit: digit(at: index),
                            isActive: codeFocused && index == min(code.count, 5)
                        )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { codeFocused = true }
            }

            if let devCode = auth.devCode {
                DevCodeHint(code: devCode) {
                    code = devCode
                }
            }

            errorLabel

            PrimaryActionButton(
                title: "Verify",
                isBusy: auth.isBusy,
                isEnabled: code.count == 6
            ) {
                Task { await auth.verifyCode(code) }
            }

            Button("Use a different number") {
                code = ""
                auth.restartSignIn()
                phoneFocused = true
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
        }
        .onAppear { codeFocused = true }
    }

    private func digit(at index: Int) -> String? {
        guard index < code.count else { return nil }
        return String(Array(code)[index])
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let message = auth.errorMessage {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.danger)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
        }
    }

    private var footer: some View {
        Label("Anonymous by default. No profile, no real name.", systemImage: "eye.slash.fill")
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .padding(.bottom, 18)
    }
}

// MARK: - Pieces

private struct CodeSlot: View {
    let digit: String?
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceElevated)
                .frame(width: 46, height: 58)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isActive ? Theme.accent : Color.clear, lineWidth: 1.5)
                )

            if let digit {
                Text(digit)
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: digit)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

private struct DevCodeHint: View {
    let code: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text("SMS delivery isn't configured yet")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(code)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(Theme.cyan)
                Text("Tap to fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PrimaryActionButton: View {
    let title: String
    var isBusy: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                isEnabled && !isBusy
                    ? AnyShapeStyle(Theme.accentGradient)
                    : AnyShapeStyle(Theme.surfaceElevated),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .foregroundStyle(isEnabled ? .black : Theme.textTertiary)
        }
        .disabled(!isEnabled || isBusy)
        .animation(.easeOut(duration: 0.2), value: isEnabled)
    }
}

/// Slow-drifting scan lines that give the auth screen depth without a photo.
private struct ScannerBackdrop: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(Theme.accent.opacity(0.05), lineWidth: 1)
                        .frame(width: geo.size.width * (0.9 + CGFloat(index) * 0.45))
                        .offset(y: -geo.size.height * 0.18)
                }
                LinearGradient(
                    colors: [Theme.cyan.opacity(0.10), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .offset(y: phase)
            .onAppear {
                withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                    phase = 18
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
