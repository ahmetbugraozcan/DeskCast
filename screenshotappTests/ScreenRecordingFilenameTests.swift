import Foundation
import Testing
@testable import screenshotapp

struct ScreenRecordingFilenameTests {
    @Test func timestampedFilenameUsesDeskCastNameAndMovExtension() {
        let date = Date(timeIntervalSince1970: 0)
        let filename = ScreenRecordingFilename.timestampedFilename(for: date)

        #expect(filename.hasPrefix("\(AppConstants.appName)-Recording-"))
        #expect(filename.hasSuffix(".mov"))
    }
}
