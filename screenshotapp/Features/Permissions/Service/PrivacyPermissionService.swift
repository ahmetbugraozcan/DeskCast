import ApplicationServices
import AppKit
import CoreGraphics
import CoreServices
import Foundation

enum PrivacyPermissionService {
    nonisolated static func status(for permission: PrivacyPermissionID) -> PrivacyPermissionStatus {
        switch permission {
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .finderAutomation:
            return finderAutomationStatus(askUserIfNeeded: false)
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted
        }
    }

    @MainActor
    static func request(_ permission: PrivacyPermissionID) async -> PrivacyPermissionStatus {
        switch permission {
        case .screenRecording:
            return ScreenRecordingPermissionService.ensureAccess() ? .granted : .notGranted
        case .finderAutomation:
            return await Task.detached {
                finderAutomationStatus(askUserIfNeeded: true)
            }.value
        case .accessibility:
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return AXIsProcessTrusted() ? .granted : .notGranted
        }
    }

    @MainActor
    static func openSettings(for permission: PrivacyPermissionID) {
        switch permission {
        case .screenRecording:
            ScreenRecordingPermissionService.openSettings()
        case .finderAutomation:
            if let automationURL = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
            ), NSWorkspace.shared.open(automationURL) {
                return
            }

            if let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(privacyURL)
            }
        case .accessibility:
            if let accessibilityURL = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ), NSWorkspace.shared.open(accessibilityURL) {
                return
            }

            if let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(privacyURL)
            }
        }
    }

    nonisolated static func reset(_ permissions: [PrivacyPermissionID]) throws {
        for permission in Set(permissions) {
            try reset(permission)
        }
    }

    nonisolated private static func finderAutomationStatus(askUserIfNeeded: Bool) -> PrivacyPermissionStatus {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")

        guard let targetPointer = descriptor.aeDesc else {
            return .unavailable
        }

        var target = targetPointer.pointee
        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(kCoreEventClass),
            AEEventID(kAEGetData),
            askUserIfNeeded
        )

        switch Int(status) {
        case Int(noErr):
            return .granted
        case errAEEventNotPermitted, errAEEventWouldRequireUserConsent:
            return .notGranted
        case procNotFound:
            return .unavailable
        default:
            return .notGranted
        }
    }

    nonisolated private static func reset(_ permission: PrivacyPermissionID) throws {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", permission.tccServiceName, resetBundleIdentifier]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw PrivacyPermissionResetError.launchFailed(permission: permission, underlyingError: error)
        }

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw PrivacyPermissionResetError.commandFailed(permission: permission, output: output)
        }
    }

    nonisolated private static var resetBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.ahmetbugraozcan.screenshotapp"
    }
}

enum PrivacyPermissionResetError: LocalizedError {
    case launchFailed(permission: PrivacyPermissionID, underlyingError: Error)
    case commandFailed(permission: PrivacyPermissionID, output: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let permission, let underlyingError):
            return AppLocalization.formatted(
                "Could not reset %@: %@",
                permission.title,
                underlyingError.localizedDescription
            )
        case .commandFailed(let permission, let output):
            if output.isEmpty {
                return AppLocalization.formatted("Could not reset %@.", permission.title)
            }

            return AppLocalization.formatted("Could not reset %@: %@", permission.title, output)
        }
    }
}
