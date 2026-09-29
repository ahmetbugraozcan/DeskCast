import AppKit
import CoreImage.CIFilterBuiltins
import Testing
@testable import screenshotapp

struct BarcodeReadingTests {
    @Test func readsAGeneratedQRCode() async throws {
        let image = try #require(Self.qrImage(for: "https://example.com/deskcast"))

        let payloads = await VisionBarcodeReadingService().payloads(in: image)

        #expect(payloads == ["https://example.com/deskcast"])
    }

    @Test func blankImageHasNoCodes() async {
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }

        #expect(await VisionBarcodeReadingService().payloads(in: image).isEmpty)
    }

    @Test func payloadsAreTrimmedAndDeduplicated() {
        #expect(VisionBarcodeReadingService.uniquePayloads([" a ", "b", "a", "", "  "]) == ["a", "b"])
    }

    private static func qrImage(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)

        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: output.extent.size)
    }
}
