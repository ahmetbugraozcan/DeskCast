import Foundation

enum ScreenRecordingFilename {
    static func timestampedFilename(
        for date: Date,
        prefix: String = ScreenRecordingSettings.defaultFilenamePrefix
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        let sanitizedPrefix = prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let resolvedPrefix = sanitizedPrefix.isEmpty
            ? ScreenRecordingSettings.defaultFilenamePrefix
            : sanitizedPrefix

        return "\(resolvedPrefix)-\(formatter.string(from: date)).mov"
    }
}
