import AppKit
import Vision

protocol BarcodeReading: Sendable {
    /// Payloads of the QR codes and barcodes in `image`, top to bottom, without
    /// duplicates; empty when there are none.
    func payloads(in image: NSImage) async -> [String]
}

struct VisionBarcodeReadingService: BarcodeReading {
    func payloads(in image: NSImage) async -> [String] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectBarcodesRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                guard (try? handler.perform([request])) != nil else {
                    continuation.resume(returning: [])
                    return
                }

                // Vision's origin is bottom-left, so a higher midY is nearer the top.
                let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                continuation.resume(returning: Self.uniquePayloads(observations.compactMap(\.payloadStringValue)))
            }
        }
    }

    static func uniquePayloads(_ payloads: [String]) -> [String] {
        var seen = Set<String>()

        return payloads
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
