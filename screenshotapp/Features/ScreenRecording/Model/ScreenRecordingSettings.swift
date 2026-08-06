import Foundation

enum ScreenRecordingMode: String, CaseIterable, Identifiable {
    case entireScreen
    case selectedArea

    var id: String { rawValue }
}

enum ScreenRecordingFrameRate: Int, CaseIterable, Identifiable {
    case twentyFour = 24
    case thirty = 30
    case sixty = 60
    case oneTwenty = 120

    var id: Int { rawValue }
}

enum ScreenRecordingQuality: String, CaseIterable, Identifiable {
    case high
    case balanced
    case small

    var id: String { rawValue }

    /// Target bits per pixel-per-frame, tuned per codec. HEVC is more efficient,
    /// so it needs fewer bits for comparable perceived sharpness of screen/text.
    func bitsPerPixelPerFrame(codec: ScreenRecordingCodec) -> Double {
        switch (self, codec) {
        case (.high, .h264): 0.20
        case (.balanced, .h264): 0.11
        case (.small, .h264): 0.06
        case (.high, .hevc): 0.12
        case (.balanced, .hevc): 0.07
        case (.small, .hevc): 0.04
        }
    }
}

enum ScreenRecordingCodec: String, CaseIterable, Identifiable {
    case h264
    case hevc

    var id: String { rawValue }
}

struct ScreenRecordingSettingsSnapshot {
    let saveDirectoryPath: String
    let filenamePrefix: String
    let defaultMode: ScreenRecordingMode
    let capturesSystemAudio: Bool
    let capturesMicrophone: Bool
    let microphoneDeviceID: String
    let showsCursor: Bool
    let showsMouseClicks: Bool
    let frameRate: ScreenRecordingFrameRate
    let quality: ScreenRecordingQuality
    let codec: ScreenRecordingCodec
    let countdownSeconds: Int

    var saveDirectoryURL: URL {
        URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
    }
}

enum ScreenRecordingSettings {
    enum Keys {
        static let saveDirectoryPath = "screenRecording.saveDirectoryPath"
        static let filenamePrefix = "screenRecording.filenamePrefix"
        static let defaultMode = "screenRecording.defaultMode"
        static let capturesSystemAudio = "screenRecording.capturesSystemAudio"
        static let capturesMicrophone = "screenRecording.capturesMicrophone"
        static let microphoneDeviceID = "screenRecording.microphoneDeviceID"
        static let showsCursor = "screenRecording.showsCursor"
        static let showsMouseClicks = "screenRecording.showsMouseClicks"
        static let frameRate = "screenRecording.frameRate"
        static let quality = "screenRecording.quality"
        static let codec = "screenRecording.codec"
        static let countdownSeconds = "screenRecording.countdownSeconds"
    }

    static let defaultSaveDirectoryPath = FileManager.default.urls(
        for: .moviesDirectory,
        in: .userDomainMask
    ).first?.appendingPathComponent(AppConstants.appName, isDirectory: true).path
        ?? NSHomeDirectory().appending("/Movies/\(AppConstants.appName)")
    static let defaultFilenamePrefix = "\(AppConstants.appName)-Recording"
    static let defaultMode = ScreenRecordingMode.selectedArea
    static let defaultCapturesSystemAudio = true
    static let defaultCapturesMicrophone = false
    static let defaultMicrophoneDeviceID = ""
    static let defaultShowsCursor = true
    static let defaultShowsMouseClicks = false
    static let defaultFrameRate = ScreenRecordingFrameRate.thirty
    static let defaultQuality = ScreenRecordingQuality.high
    static let defaultCodec = ScreenRecordingCodec.h264
    static let defaultCountdownSeconds = 3
    static let countdownOptions = [0, 3, 5]

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: defaultValues)
    }

    static func resetToDefaults(in defaults: UserDefaults = .standard) {
        for (key, value) in defaultValues {
            defaults.set(value, forKey: key)
        }
    }

    static func snapshot(from defaults: UserDefaults = .standard) -> ScreenRecordingSettingsSnapshot {
        let directoryPath = defaults.string(forKey: Keys.saveDirectoryPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefix = defaults.string(forKey: Keys.filenamePrefix)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let modeRaw = defaults.string(forKey: Keys.defaultMode) ?? ""
        let frameRateValue = defaults.integer(forKey: Keys.frameRate)

        return ScreenRecordingSettingsSnapshot(
            saveDirectoryPath: directoryPath.isEmpty ? defaultSaveDirectoryPath : directoryPath,
            filenamePrefix: prefix.isEmpty ? defaultFilenamePrefix : prefix,
            defaultMode: ScreenRecordingMode(rawValue: modeRaw) ?? defaultMode,
            capturesSystemAudio: defaults.bool(forKey: Keys.capturesSystemAudio),
            capturesMicrophone: defaults.bool(forKey: Keys.capturesMicrophone),
            microphoneDeviceID: defaults.string(forKey: Keys.microphoneDeviceID) ?? "",
            showsCursor: defaults.bool(forKey: Keys.showsCursor),
            showsMouseClicks: defaults.bool(forKey: Keys.showsMouseClicks),
            frameRate: ScreenRecordingFrameRate(rawValue: frameRateValue) ?? defaultFrameRate,
            quality: ScreenRecordingQuality(rawValue: defaults.string(forKey: Keys.quality) ?? "")
                ?? defaultQuality,
            codec: ScreenRecordingCodec(rawValue: defaults.string(forKey: Keys.codec) ?? "")
                ?? defaultCodec,
            countdownSeconds: defaults.object(forKey: Keys.countdownSeconds) == nil
                ? defaultCountdownSeconds
                : max(0, defaults.integer(forKey: Keys.countdownSeconds))
        )
    }

    private static var defaultValues: [String: Any] {
        [
            Keys.saveDirectoryPath: defaultSaveDirectoryPath,
            Keys.filenamePrefix: defaultFilenamePrefix,
            Keys.defaultMode: defaultMode.rawValue,
            Keys.capturesSystemAudio: defaultCapturesSystemAudio,
            Keys.capturesMicrophone: defaultCapturesMicrophone,
            Keys.microphoneDeviceID: defaultMicrophoneDeviceID,
            Keys.showsCursor: defaultShowsCursor,
            Keys.showsMouseClicks: defaultShowsMouseClicks,
            Keys.frameRate: defaultFrameRate.rawValue,
            Keys.quality: defaultQuality.rawValue,
            Keys.codec: defaultCodec.rawValue,
            Keys.countdownSeconds: defaultCountdownSeconds
        ]
    }
}
