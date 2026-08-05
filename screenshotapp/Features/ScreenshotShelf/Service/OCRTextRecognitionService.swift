import AppKit
import Vision

enum OCRTextRecognitionService {
    static func recognizeText(in image: NSImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            recognizeText(in: image) { result in
                continuation.resume(with: result)
            }
        }
    }

    static func recognizeText(
        in image: NSImage,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(OCRTextRecognitionError.imageConversionFailed))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, Error>

            do {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])

                let lines = (request.results ?? [])
                    .compactMap { observation in
                        observation.topCandidates(1).first?.string
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .filter { !$0.isEmpty }

                if lines.isEmpty {
                    result = .failure(OCRTextRecognitionError.noTextFound)
                } else {
                    result = .success(lines.joined(separator: "\n"))
                }
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}

enum OCRTextRecognitionError: Error {
    case imageConversionFailed
    case noTextFound
}
