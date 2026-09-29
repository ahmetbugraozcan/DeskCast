import AppKit

/// An 8-bit sRGB color picked from the screen.
struct PickedColor: Equatable, Hashable, Identifiable {
    let red: Int
    let green: Int
    let blue: Int

    var id: String { hex }

    init(red: Int, green: Int, blue: Int) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
    }

    /// Converts any color into sRGB first, so the numbers match what design
    /// tools show for the same pixel.
    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }

        self.init(
            red: Int((srgb.redComponent * 255).rounded()),
            green: Int((srgb.greenComponent * 255).rounded()),
            blue: Int((srgb.blueComponent * 255).rounded())
        )
    }

    /// Parses `#RRGGBB` or `RRGGBB`.
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }

        self.init(red: (value >> 16) & 0xFF, green: (value >> 8) & 0xFF, blue: value & 0xFF)
    }

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    func formatted(_ format: ColorCopyFormat) -> String {
        switch format {
        case .hex:
            return hex
        case .rgb:
            return "rgb(\(red), \(green), \(blue))"
        case .hsl:
            let hsl = hsl
            return "hsl(\(hsl.hue), \(hsl.saturation)%, \(hsl.lightness)%)"
        case .swiftUI:
            return String(
                format: "Color(red: %.3f, green: %.3f, blue: %.3f)",
                Double(red) / 255,
                Double(green) / 255,
                Double(blue) / 255
            )
        }
    }

    private struct HSL {
        let hue: Int
        let saturation: Int
        let lightness: Int
    }

    /// Hue in degrees, saturation and lightness in percent, all rounded.
    private var hsl: HSL {
        let red = Double(red) / 255
        let green = Double(green) / 255
        let blue = Double(blue) / 255
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        let lightness = (maxValue + minValue) / 2

        guard delta > 0 else {
            return HSL(hue: 0, saturation: 0, lightness: Int((lightness * 100).rounded()))
        }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double

        switch maxValue {
        case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }

        hue *= 60
        if hue < 0 { hue += 360 }

        return HSL(
            hue: Int(hue.rounded()) % 360,
            saturation: Int((saturation * 100).rounded()),
            lightness: Int((lightness * 100).rounded())
        )
    }

    private static func clamped(_ value: Int) -> Int {
        min(max(value, 0), 255)
    }
}

/// How a picked color is written to the clipboard.
enum ColorCopyFormat: String, CaseIterable, Identifiable {
    case hex
    case rgb
    case hsl
    case swiftUI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hex: "HEX"
        case .rgb: "RGB"
        case .hsl: "HSL"
        case .swiftUI: "SwiftUI"
        }
    }
}

enum ColorPickerSettings {
    enum Keys {
        static let copyFormat = "colorPicker.copyFormat"
        /// Recently picked colors as `#RRGGBB`, newest first.
        static let recentColors = "colorPicker.recentColors"
    }

    static let defaultCopyFormat = ColorCopyFormat.hex
    static let recentColorLimit = 8

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Keys.copyFormat: defaultCopyFormat.rawValue,
            Keys.recentColors: [String]()
        ])
    }

    /// Puts `color` first, drops an older copy of it and keeps the list short.
    static func updatedRecents(_ recents: [PickedColor], adding color: PickedColor) -> [PickedColor] {
        Array(([color] + recents.filter { $0 != color }).prefix(recentColorLimit))
    }
}
