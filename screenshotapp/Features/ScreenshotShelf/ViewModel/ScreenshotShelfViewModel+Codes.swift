import AppKit

extension ScreenshotShelfViewModel {
    /// Copies what the QR codes / barcodes in a Capture OCR selection contain.
    func copyCodePayloads(_ payloads: [String]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard pasteboard.setString(payloads.joined(separator: "\n"), forType: .string) else {
            NSSound.beep()
            showToast(AppLocalization.string("Could not copy text"), systemImage: "exclamationmark.triangle.fill")
            return
        }

        let isLink = payloads.count == 1 && URL(string: payloads[0]).map { ["http", "https"].contains($0.scheme?.lowercased()) } == true
        let message = payloads.count > 1
            ? AppLocalization.formatted("ocr.codes.copied", payloads.count)
            : AppLocalization.string(isLink ? "ocr.code.linkCopied" : "ocr.code.copied")
        showToast(message, systemImage: "qrcode")
    }
}
