//
//  DataScannerRepresentable.swift
//  RocketChat
//

import SwiftUI
import VisionKit

/// Live camera scanner backed by VisionKit's `DataScannerViewController`.
/// Recognises QR codes / barcodes and text (plates, signs) in one pass.
struct DataScannerRepresentable: UIViewControllerRepresentable {
    /// Called with the decoded value and the inferred kind.
    let onScan: (String, TagKind) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(), .text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        try? uiViewController.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String, TagKind) -> Void
        private var lastValue: String?

        init(onScan: @escaping (String, TagKind) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle(item)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard let first = addedItems.first else { return }
            handle(first)
        }

        private func handle(_ item: RecognizedItem) {
            switch item {
            case .barcode(let barcode):
                guard let value = barcode.payloadStringValue, value != lastValue else { return }
                lastValue = value
                onScan(value, .qrCode)
            case .text(let text):
                let value = text.transcript
                guard !value.isEmpty, value != lastValue else { return }
                lastValue = value
                onScan(value, inferKind(from: value))
            @unknown default:
                break
            }
        }

        /// Plates are short, uppercase, alphanumeric; longer strings read as signs.
        private func inferKind(from value: String) -> TagKind {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let compact = cleaned.filter { $0.isLetter || $0.isNumber }
            if compact.count <= 8 && cleaned.split(separator: " ").count <= 2 {
                return .licensePlate
            }
            return .sign
        }
    }
}
