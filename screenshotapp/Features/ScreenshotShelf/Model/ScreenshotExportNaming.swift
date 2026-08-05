import Foundation

struct ScreenshotExportOption: Identifiable, Hashable {
    let prefix: String
    let variant: String?

    var id: String {
        filenameStem
    }

    var filenameStem: String {
        if let variant, !variant.isEmpty {
            return "\(prefix)-\(variant)"
        }

        return prefix
    }

    var filename: String {
        "\(filenameStem).png"
    }
}

enum ScreenshotExportNaming {
    static let defaultPrefix = "app-store"
    static let defaultVariants = "small, medium, large"

    static func options(prefix: String, variants: String) -> [ScreenshotExportOption] {
        let sanitizedPrefix = sanitizedFilenameComponent(
            prefix,
            fallback: "screenshot"
        )
        let sanitizedVariants = parsedVariants(from: variants)
            .map { sanitizedFilenameComponent($0, fallback: "") }
            .filter { !$0.isEmpty }

        guard !sanitizedVariants.isEmpty else {
            return [
                ScreenshotExportOption(prefix: sanitizedPrefix, variant: nil)
            ]
        }

        return sanitizedVariants.map { variant in
            ScreenshotExportOption(prefix: sanitizedPrefix, variant: variant)
        }
    }

    static func timestampedFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        return "\(AppConstants.appName)-\(formatter.string(from: date)).png"
    }

    private static func parsedVariants(from variants: String) -> [String] {
        variants
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func sanitizedFilenameComponent(
        _ value: String,
        fallback: String
    ) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var result = ""
        var lastWasSeparator = false

        for scalar in value.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            if allowedCharacters.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }

        let sanitized = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return sanitized.isEmpty ? fallback : sanitized
    }
}
