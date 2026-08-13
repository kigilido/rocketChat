//
//  ARDepthScannerView.swift
//  RocketChat
//

import SwiftUI
import ARKit
import RealityKit

/// Depth-aware AR scanner. On supported hardware it runs world tracking with
/// scene depth (and LiDAR mesh when available) so scanned tags can be anchored
/// in space. On the simulator / unsupported devices it shows a placeholder.
struct ARDepthScannerView: View {
    var body: some View {
        Group {
            #if targetEnvironment(simulator)
            ARUnavailablePlaceholder()
            #else
            if ARWorldTrackingConfiguration.isSupported {
                ARDepthContainer()
                    .ignoresSafeArea()
            } else {
                ARUnavailablePlaceholder()
            }
            #endif
        }
    }
}

private struct ARDepthContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        arView.session.run(config)

        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.topAnchor.constraint(equalTo: arView.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
            coaching.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: arView.trailingAnchor)
        ])

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

struct ARUnavailablePlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arkit")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Depth Scanning")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Install this app on your device\nvia the Rork App to use AR depth scanning.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
