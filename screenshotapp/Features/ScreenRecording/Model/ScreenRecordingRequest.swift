import CoreGraphics
import Foundation

struct ScreenRecordingDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let scaleFactor: CGFloat
}

struct ScreenRecordingMicrophone: Identifiable, Equatable {
    let id: String
    let name: String
}

struct ScreenRecordingRequest {
    let display: ScreenRecordingDisplay
    /// Display-local rectangle in points, using a top-left origin. Nil records
    /// the complete display.
    let sourceRect: CGRect?
    let destinationURL: URL
    let capturesSystemAudio: Bool
    let capturesMicrophone: Bool
    let microphoneDeviceID: String?
    let showsCursor: Bool
    let showsMouseClicks: Bool
    let frameRate: Int
    let quality: ScreenRecordingQuality
    let codec: ScreenRecordingCodec
}

enum ScreenRecordingServiceError: LocalizedError {
    case displayUnavailable
    case alreadyRecording
    case notRecording
    case outputConfigurationFailed
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            "The selected display is no longer available."
        case .alreadyRecording:
            "A recording is already in progress."
        case .notRecording:
            "No recording is in progress."
        case .outputConfigurationFailed:
            "The recording output could not be configured."
        case .captureFailed(let message):
            message
        }
    }
}
