import Foundation
import Testing
@testable import screenshotapp

struct ScreenRecordingServiceTests {
    @Test func settingsRegisterIndependentVideoDefaults() throws {
        let suiteName = "ScreenRecordingSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        ScreenRecordingSettings.registerDefaults(in: defaults)
        let snapshot = ScreenRecordingSettings.snapshot(from: defaults)

        #expect(snapshot.defaultMode == .selectedArea)
        #expect(snapshot.capturesSystemAudio)
        #expect(!snapshot.capturesMicrophone)
        #expect(snapshot.saveDirectoryPath == ScreenRecordingSettings.defaultSaveDirectoryPath)

        defaults.removePersistentDomain(forName: suiteName)
    }
}

struct ToastStyleTests {
    @Test func errorSymbolsInferErrorStyle() {
        #expect(ToastStyle.inferred(from: "exclamationmark.triangle.fill") == .error)
        #expect(ToastStyle.inferred(from: "xmark.circle.fill") == .error)
    }

    @Test func defaultSymbolInfersSuccessStyle() {
        #expect(ToastStyle.inferred(from: "checkmark.circle.fill") == .success)
    }
}
