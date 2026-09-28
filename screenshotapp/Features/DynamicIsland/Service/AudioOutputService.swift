import AudioToolbox
import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

/// System output/input volume and device selection through CoreAudio.
/// macOS exposes no per-app volume without installing an audio driver, so the
/// mixer works on devices, not apps.
@MainActor
final class AudioOutputService {
    // MARK: - Devices

    func defaultDevice(input: Bool = false) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    func outputDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }

        return ids.compactMap { id in
            guard hasOutputStreams(id), let name = deviceName(id) else { return nil }
            return AudioDevice(id: id, name: name)
        }
    }

    func setDefaultOutputDevice(_ id: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = id

        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
    }

    func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue()
        else {
            return nil
        }

        return value as String
    }

    /// Persistent UID, needed to build aggregate devices on this output.
    func deviceUID(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &uid) == noErr,
              let value = uid?.takeRetainedValue()
        else {
            return nil
        }

        return value as String
    }

    private func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    // MARK: - Volume

    /// 0...1, or nil when the device has no software volume (e.g. some HDMI).
    func volume(input: Bool = false) -> Double? {
        guard let device = defaultDevice(input: input) else { return nil }

        var address = virtualMainVolumeAddress(input: input)
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)

        guard AudioHardwareServiceGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else {
            return nil
        }

        return Double(volume)
    }

    func setVolume(_ value: Double, input: Bool = false) {
        guard let device = defaultDevice(input: input) else { return }

        var address = virtualMainVolumeAddress(input: input)
        var volume = Float32(min(max(value, 0), 1))

        AudioHardwareServiceSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)

        // Raising the volume should also unmute, like the system slider does.
        if !input, value > 0, isMuted() {
            setMuted(false)
        }
    }

    func isMuted(input: Bool = false) -> Bool {
        guard let device = defaultDevice(input: input) else { return false }

        var address = muteAddress(input: input)
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else {
            return false
        }

        return muted != 0
    }

    /// Returns false when the device can't be muted in software.
    @discardableResult
    func setMuted(_ muted: Bool, input: Bool = false) -> Bool {
        guard let device = defaultDevice(input: input) else { return false }

        var address = muteAddress(input: input)
        var value = UInt32(muted ? 1 : 0)
        var settable = DarwinBoolean(false)

        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            return false
        }

        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private func virtualMainVolumeAddress(input: Bool) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func muteAddress(input: Bool) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
