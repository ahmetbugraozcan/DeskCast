import Foundation
import Testing
@testable import screenshotapp

struct ScreenshotExportNamingTests {

    @Test func optionsSplitsVariantsAndSanitizesPrefix() {
        let options = ScreenshotExportNaming.options(prefix: "App Store", variants: "small, medium, large")

        #expect(options.count == 3)
        #expect(options.map(\.filename) == [
            "App-Store-small.png",
            "App-Store-medium.png",
            "App-Store-large.png"
        ])
    }

    @Test func optionsWithoutVariantsProducesSinglePrefixFile() {
        let options = ScreenshotExportNaming.options(prefix: "shot", variants: "   ")

        #expect(options.count == 1)
        #expect(options.first?.variant == nil)
        #expect(options.first?.filename == "shot.png")
    }

    @Test func optionsFallsBackToDefaultStemForEmptyPrefix() {
        let options = ScreenshotExportNaming.options(prefix: "", variants: "")

        #expect(options.count == 1)
        #expect(options.first?.filename == "screenshot.png")
    }

    @Test func optionsAcceptsSemicolonAndNewlineSeparators() {
        let options = ScreenshotExportNaming.options(prefix: "p", variants: "a; b\nc")

        #expect(options.map(\.variant) == ["a", "b", "c"])
    }

    @Test func timestampedFilenameUsesAppNameAndPngExtension() {
        let date = Date(timeIntervalSince1970: 0)
        let name = ScreenshotExportNaming.timestampedFilename(for: date)

        #expect(name.hasPrefix("\(AppConstants.appName)-"))
        #expect(name.hasSuffix(".png"))
    }
}
