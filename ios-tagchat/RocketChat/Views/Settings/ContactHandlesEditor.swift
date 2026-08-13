//
//  ContactHandlesEditor.swift
//  RocketChat
//
//  Social handles the user is willing to share — revealed only after a mutual
//  contact request is accepted.
//

import SwiftUI

struct ContactHandlesEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    @State private var instagram: String = ""
    @State private var whatsapp: String = ""
    @State private var telegram: String = ""
    @State private var other: String = ""
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        lockNotice

                        HandleField(
                            icon: "camera.fill",
                            tint: Color(hex: 0xE1306C),
                            label: "Instagram",
                            prompt: "username",
                            text: $instagram
                        )
                        HandleField(
                            icon: "phone.fill",
                            tint: Color(hex: 0x25D366),
                            label: "WhatsApp",
                            prompt: "+1 555 000 1234",
                            text: $whatsapp,
                            keyboard: .phonePad
                        )
                        HandleField(
                            icon: "paperplane.fill",
                            tint: Color(hex: 0x2AABEE),
                            label: "Telegram",
                            prompt: "username",
                            text: $telegram
                        )
                        HandleField(
                            icon: "link",
                            tint: Theme.cyan,
                            label: "Anything else",
                            prompt: "Discord, email, a link…",
                            text: $other
                        )

                        PrimaryActionButton(
                            title: "Save handles",
                            isBusy: isSaving,
                            isEnabled: true
                        ) {
                            save()
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Social Handles")
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
        .onAppear {
            instagram = auth.handles.instagram ?? ""
            whatsapp = auth.handles.whatsapp ?? ""
            telegram = auth.handles.telegram ?? ""
            other = auth.handles.other ?? ""
        }
    }

    private var lockNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Nobody sees these until you accept a contact request from them. Leave any field blank to keep it private.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            await auth.saveHandles(ContactHandles(
                instagram: instagram,
                whatsapp: whatsapp,
                telegram: telegram,
                other: other
            ))
            dismiss()
        }
    }
}

private struct HandleField: View {
    let icon: String
    let tint: Color
    let label: String
    let prompt: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
            }

            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.textTertiary))
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .padding(14)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
