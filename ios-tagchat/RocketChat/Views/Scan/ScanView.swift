//
//  ScanView.swift
//  RocketChat
//

import SwiftUI
import SwiftData
import VisionKit

/// The Scan tab. Lets the user point the camera at a plate / QR / sign to start
/// an anonymous chat. Offers a fast code-scanning mode and a depth-aware AR mode.
struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(IdentityStore.self) private var identity
    @Environment(LocationService.self) private var location

    @State private var viewModel = ScanViewModel()
    @State private var mode: ScanMode = .code

    var onOpenConversation: (Conversation) -> Void

    enum ScanMode: String, CaseIterable, Identifiable {
        case code = "Code & Text"
        case depth = "AR Depth"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                scanner
                    .ignoresSafeArea(edges: .bottom)

                VStack {
                    modePicker
                        .padding(.horizontal)
                        .padding(.top, 8)
                    Spacer()
                    if mode == .code {
                        ReticleHint()
                            .padding(.bottom, 40)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $viewModel.isPresentingResult) {
                ScanResultSheet(viewModel: viewModel) {
                    commit()
                }
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { location.refresh() }
    }

    @ViewBuilder
    private var scanner: some View {
        switch mode {
        case .code:
            CodeScannerProxy { value, kind in
                viewModel.handleDetection(value: value, kind: kind)
            }
        case .depth:
            ARDepthScannerView()
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(ScanMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private func commit() {
        let conversation = viewModel.commit(
            context: modelContext,
            handle: identity.handle,
            location: location.lastLocation,
            placeName: nil,
            ttl: identity.defaultTTL
        )
        Task {
            if let loc = location.lastLocation,
               let name = await location.placeName(for: loc) {
                _ = name
            }
        }
        viewModel.reset()
        if let conversation {
            onOpenConversation(conversation)
        }
    }
}

/// Wraps the live data scanner with a camera-availability check so the app
/// still renders cleanly in the cloud simulator.
private struct CodeScannerProxy: View {
    let onScan: (String, TagKind) -> Void

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            DataScannerRepresentable(onScan: onScan)
        } else {
            CameraUnavailablePlaceholder()
        }
    }
}

private struct CameraUnavailablePlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "viewfinder")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Scanner")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Install this app on your device\nvia the Rork App to use the camera.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// Animated framing reticle shown over the live scanner.
private struct ReticleHint: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 3)
                .frame(width: 230, height: 150)
                .shadow(color: Theme.accent.opacity(0.6), radius: pulse ? 18 : 6)
                .scaleEffect(pulse ? 1.02 : 0.98)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            Text("Aim at a plate, QR code, or sign")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .onAppear { pulse = true }
    }
}
