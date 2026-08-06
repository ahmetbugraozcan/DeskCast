import Foundation

// Localized permission labels, kept in the presentation layer.

extension PrivacyPermissionID {
    nonisolated var title: String {
        switch self {
        case .screenRecording: AppLocalization.string("Screen Recording")
        case .microphone: AppLocalization.string("Microphone")
        case .finderAutomation: AppLocalization.string("Finder Automation")
        case .accessibility: AppLocalization.string("Accessibility")
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .screenRecording:
            AppLocalization.string("Required by Capture Selected Area, Video Recording, and Capture OCR.")
        case .microphone:
            AppLocalization.string("Required only when microphone recording is enabled.")
        case .finderAutomation:
            AppLocalization.string("Required to read the front Finder window path.")
        case .accessibility:
            AppLocalization.string("Required to open Drop Shelf from the shake gesture.")
        }
    }
}

extension PrivacyPermissionStatus {
    nonisolated var title: String {
        switch self {
        case .checking: AppLocalization.string("Checking")
        case .granted: AppLocalization.string("Granted")
        case .notGranted: AppLocalization.string("Not Granted")
        case .unavailable: AppLocalization.string("Unavailable")
        }
    }
}
