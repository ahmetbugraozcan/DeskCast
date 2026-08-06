import Foundation

enum PrivacyPermissionID: String, CaseIterable, Identifiable, Hashable, Sendable {
    case screenRecording
    case microphone
    case finderAutomation
    case accessibility

    nonisolated var id: String { rawValue }

    nonisolated var systemImage: String {
        switch self {
        case .screenRecording: "record.circle"
        case .microphone: "mic"
        case .finderAutomation: "folder.badge.gearshape"
        case .accessibility: "accessibility"
        }
    }

    nonisolated var tccServiceName: String {
        switch self {
        case .screenRecording: "ScreenCapture"
        case .microphone: "Microphone"
        case .finderAutomation: "AppleEvents"
        case .accessibility: "Accessibility"
        }
    }
}

enum PrivacyPermissionStatus: Equatable, Sendable {
    case checking
    case granted
    case notGranted
    case unavailable

    nonisolated var systemImage: String {
        switch self {
        case .checking: "hourglass"
        case .granted: "checkmark.circle.fill"
        case .notGranted: "xmark.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    nonisolated var isGranted: Bool {
        switch self {
        case .granted:
            return true
        case .checking, .notGranted, .unavailable:
            return false
        }
    }
}
