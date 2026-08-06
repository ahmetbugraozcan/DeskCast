import AppKit
import AVFoundation
import CoreGraphics

protocol ScreenRecordingSourceProviding {
    func availableDisplays() -> [ScreenRecordingDisplay]
    func availableMicrophones() -> [ScreenRecordingMicrophone]
}

struct ScreenRecordingSourceService: ScreenRecordingSourceProviding {
    func availableDisplays() -> [ScreenRecordingDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return nil
            }

            return ScreenRecordingDisplay(
                id: number.uint32Value,
                name: screen.localizedName,
                frame: screen.frame,
                scaleFactor: screen.backingScaleFactor
            )
        }
    }

    func availableMicrophones() -> [ScreenRecordingMicrophone] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        var seenIDs = Set<String>()
        return discovery.devices.compactMap { device in
            guard seenIDs.insert(device.uniqueID).inserted else {
                return nil
            }

            return ScreenRecordingMicrophone(id: device.uniqueID, name: device.localizedName)
        }
    }
}
