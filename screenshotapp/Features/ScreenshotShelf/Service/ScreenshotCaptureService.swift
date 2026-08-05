import AppKit

enum ScreenshotCaptureError: Error {
    case cancelled
    case commandFailed(status: Int32, message: String)
    case pasteboardImageMissing

    var isLikelyPermissionProblem: Bool {
        switch self {
        case .cancelled:
            return false
        case .commandFailed(_, let message):
            let lowercasedMessage = message.lowercased()
            return lowercasedMessage.contains("not authorized")
                || lowercasedMessage.contains("permission")
                || lowercasedMessage.contains("privacy")
        case .pasteboardImageMissing:
            return false
        }
    }
}

enum ScreenshotCaptureService {
    static func captureSelectedArea(
        preserveClipboard: Bool,
        completion: @escaping (Result<NSImage, ScreenshotCaptureError>) -> Void
    ) {
        let pasteboard = NSPasteboard.general
        let initialPasteboardChangeCount = pasteboard.changeCount
        let initialPasteboardSnapshot = preserveClipboard ? PasteboardSnapshot(from: pasteboard) : nil

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-c"]
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.commandFailed(
                        status: -1,
                        message: error.localizedDescription
                    )))
                }
                return
            }

            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                DispatchQueue.main.async {
                    if isCancellation(status: process.terminationStatus, message: message) {
                        completion(.failure(.cancelled))
                        return
                    }

                    completion(.failure(.commandFailed(
                        status: process.terminationStatus,
                        message: message
                    )))
                }
                return
            }

            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general

                guard pasteboard.changeCount != initialPasteboardChangeCount else {
                    completion(.failure(.cancelled))
                    return
                }

                let image = pasteboard.readObjects(
                    forClasses: [NSImage.self],
                    options: nil
                )?.first as? NSImage

                guard let image else {
                    initialPasteboardSnapshot?.restore(to: pasteboard)
                    completion(.failure(.pasteboardImageMissing))
                    return
                }

                let capturedImage = image.detachedCopy()
                initialPasteboardSnapshot?.restore(to: pasteboard)

                completion(.success(capturedImage))
            }
        }
    }

    private static func isCancellation(status: Int32, message: String) -> Bool {
        let lowercasedMessage = message.lowercased()

        if lowercasedMessage.contains("cancel") || lowercasedMessage.contains("escape") {
            return true
        }

        if lowercasedMessage.contains("could not create image from rect") {
            return true
        }

        return status == 1 && lowercasedMessage.isEmpty
    }
}

private struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    init(from pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            let copiedItem = NSPasteboardItem()

            for type in item.types {
                if let data = item.data(forType: type) {
                    copiedItem.setData(data, forType: type)
                } else if let string = item.string(forType: type) {
                    copiedItem.setString(string, forType: type)
                }
            }

            return copiedItem
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}

private extension NSImage {
    func detachedCopy() -> NSImage {
        guard let data = tiffRepresentation, let image = NSImage(data: data) else {
            return copy() as? NSImage ?? self
        }

        return image
    }
}
