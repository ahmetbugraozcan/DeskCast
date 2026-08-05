import Foundation

enum PrivacyPermissionID: String, CaseIterable, Identifiable, Hashable, Sendable {
    case screenRecording
    case finderAutomation
    case accessibility

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .screenRecording: AppLocalization.string("Screen Recording")
        case .finderAutomation: AppLocalization.string("Finder Automation")
        case .accessibility: AppLocalization.string("Accessibility")
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .screenRecording:
            AppLocalization.string("Required by Capture Selected Area and Capture OCR.")
        case .finderAutomation:
            AppLocalization.string("Required to read the front Finder window path.")
        case .accessibility:
            AppLocalization.string("Required to open Drop Shelf from the shake gesture.")
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .screenRecording: "record.circle"
        case .finderAutomation: "folder.badge.gearshape"
        case .accessibility: "accessibility"
        }
    }

    nonisolated var tccServiceName: String {
        switch self {
        case .screenRecording: "ScreenCapture"
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

    nonisolated var title: String {
        switch self {
        case .checking: AppLocalization.string("Checking")
        case .granted: AppLocalization.string("Granted")
        case .notGranted: AppLocalization.string("Not Granted")
        case .unavailable: AppLocalization.string("Unavailable")
        }
    }

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
