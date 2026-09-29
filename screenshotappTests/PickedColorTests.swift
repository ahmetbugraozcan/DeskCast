import AppKit
import Testing
@testable import screenshotapp

struct PickedColorTests {
    @Test func formatsEveryCopyFormat() {
        let color = PickedColor(red: 255, green: 128, blue: 0)

        #expect(color.formatted(.hex) == "#FF8000")
        #expect(color.formatted(.rgb) == "rgb(255, 128, 0)")
        #expect(color.formatted(.hsl) == "hsl(30, 100%, 50%)")
        #expect(color.formatted(.swiftUI) == "Color(red: 1.000, green: 0.502, blue: 0.000)")
    }

    @Test func grayHasNoHueOrSaturation() {
        #expect(PickedColor(red: 128, green: 128, blue: 128).formatted(.hsl) == "hsl(0, 0%, 50%)")
    }

    @Test func blueHueWrapsCorrectly() {
        #expect(PickedColor(red: 0, green: 0, blue: 255).formatted(.hsl) == "hsl(240, 100%, 50%)")
        #expect(PickedColor(red: 255, green: 0, blue: 128).formatted(.hsl) == "hsl(330, 100%, 50%)")
    }

    @Test func parsesHexAndRejectsGarbage() {
        #expect(PickedColor(hex: "#1a2B3c") == PickedColor(red: 0x1A, green: 0x2B, blue: 0x3C))
        #expect(PickedColor(hex: "1A2B3C")?.hex == "#1A2B3C")
        #expect(PickedColor(hex: "#12345") == nil)
        #expect(PickedColor(hex: "zzzzzz") == nil)
    }

    @Test func convertsNSColorThroughSRGB() {
        let color = PickedColor(NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        #expect(color == PickedColor(red: 51, green: 102, blue: 153))
    }

    @Test func recentsPutNewestFirstWithoutDuplicates() {
        let red = PickedColor(red: 255, green: 0, blue: 0)
        let green = PickedColor(red: 0, green: 255, blue: 0)
        var recents = [red, green]

        recents = ColorPickerSettings.updatedRecents(recents, adding: green)
        #expect(recents == [green, red])

        for value in 0..<20 {
            recents = ColorPickerSettings.updatedRecents(recents, adding: PickedColor(red: value, green: 0, blue: 0))
        }
        #expect(recents.count == ColorPickerSettings.recentColorLimit)
        #expect(recents.first == PickedColor(red: 19, green: 0, blue: 0))
    }
}
