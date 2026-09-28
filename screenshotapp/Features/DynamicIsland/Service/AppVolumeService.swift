import AppKit
import CoreAudio

/// An app that is (or recently was) producing audio.
struct AppAudioSource: Identifiable, Equatable {
    /// Bundle identifier of the owning app; audio from its helper processes
    /// (e.g. browser renderers) is grouped under it.
    let id: String
    let name: String
    let icon: NSImage?
    let processObjectIDs: [AudioObjectID]
    let isPlaying: Bool

    static func == (lhs: AppAudioSource, rhs: AppAudioSource) -> Bool {
        lhs.id == rhs.id && lhs.processObjectIDs == rhs.processObjectIDs && lhs.isPlaying == rhs.isPlaying
    }
}

/// Per-app volume without an audio driver, using Core Audio process taps
/// (macOS 14.4+). For an app set below 100 %, DeskCast taps that app's output
/// with `mutedWhenTapped` (silencing the original), and plays the tapped audio
/// through a private aggregate device on the current output with its own gain.
/// Apps at 100 % have no tap at all, so they add no latency or CPU.
///
/// Requires the "System Audio Recording" permission; macOS asks the first time
/// a tap is created.
@MainActor
final class AppVolumeService {
    private var taps: [String: AppAudioTap] = [:]
    private var volumes: [String: Double] = [:]
    private var tapOutputUID: String?

    private static let ownBundleID = Bundle.main.bundleIdentifier ?? ""

    // MARK: - Sources

    func audioSources() -> [AppAudioSource] {
        let processObjects = Self.processObjectIDs()
        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }

        var grouped: [String: (app: NSRunningApplication, objects: [AudioObjectID], playing: Bool)] = [:]

        for object in processObjects {
            guard let bundleID = Self.bundleID(of: object), bundleID != Self.ownBundleID else { continue }

            // Helper processes ("com.google.Chrome.helper") belong to their app.
            guard let app = regularApps.first(where: { app in
                guard let appID = app.bundleIdentifier else { return false }
                return bundleID == appID || bundleID.hasPrefix(appID + ".")
            }) ?? Self.application(forPID: Self.pid(of: object)),
                let appID = app.bundleIdentifier
            else {
                continue
            }

            var entry = grouped[appID] ?? (app, [], false)
            entry.objects.append(object)
            entry.playing = entry.playing || Self.isRunningOutput(object)
            grouped[appID] = entry
        }

        return grouped
            .filter { $0.value.playing || volumes[$0.key] != nil }
            .map { appID, entry in
                AppAudioSource(
                    id: appID,
                    name: entry.app.localizedName ?? appID,
                    icon: entry.app.icon,
                    processObjectIDs: entry.objects.sorted(),
                    isPlaying: entry.playing
                )
            }
            .sorted { lhs, rhs in
                lhs.isPlaying != rhs.isPlaying ? lhs.isPlaying : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: - Volume

    func volume(for sourceID: String) -> Double {
        volumes[sourceID] ?? 1
    }

    /// Keeps taps in sync with the requested gains, the sources' current
    /// processes and the output device. Call after listing sources.
    func sync(sources: [AppAudioSource], outputUID: String?) {
        if outputUID != tapOutputUID {
            // A new output device needs new aggregate devices.
            taps.values.forEach { $0.stop() }
            taps = [:]
            tapOutputUID = outputUID
        }

        for source in sources {
            apply(volumes[source.id] ?? 1, to: source)
        }

        // Drop taps for apps that quit.
        let liveIDs = Set(sources.map(\.id))
        for (id, tap) in taps where !liveIDs.contains(id) {
            tap.stop()
            taps[id] = nil
            volumes[id] = nil
        }
    }

    func setVolume(_ value: Double, for source: AppAudioSource) {
        let value = min(max(value, 0), 1)
        volumes[source.id] = value >= 0.995 ? nil : value
        apply(value, to: source)
    }

    func stopAll() {
        taps.values.forEach { $0.stop() }
        taps = [:]
    }

    private func apply(_ value: Double, to source: AppAudioSource) {
        guard value < 0.995 else {
            taps[source.id]?.stop()
            taps[source.id] = nil
            return
        }

        if let tap = taps[source.id], tap.processObjectIDs == source.processObjectIDs {
            tap.gain.value = Float(value)
            return
        }

        taps[source.id]?.stop()
        taps[source.id] = nil

        guard let outputUID = tapOutputUID,
              let tap = AppAudioTap(processObjectIDs: source.processObjectIDs, outputUID: outputUID, gain: Float(value))
        else {
            return
        }

        taps[source.id] = tap
    }

    // MARK: - Core Audio process objects

    private static func processObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }

        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }

        return ids
    }

    private static func bundleID(of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let cfString = value?.takeRetainedValue()
        else {
            return nil
        }

        let string = cfString as String
        return string.isEmpty ? nil : string
    }

    private static func pid(of object: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = pid_t(-1)
        var size = UInt32(MemoryLayout<pid_t>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid)
        return pid
    }

    private static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)

        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    private static func application(forPID pid: pid_t) -> NSRunningApplication? {
        guard pid > 0, let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else {
            return nil
        }

        return app
    }
}

/// Gain shared with the real-time IO thread. A single aligned Float store is
/// atomic on Apple silicon/x86, which is all the audio callback needs.
nonisolated final class AudioGain: @unchecked Sendable {
    var value: Float

    init(_ value: Float) {
        self.value = value
    }
}

/// One process tap + private aggregate device + IO proc that re-plays the
/// tapped audio at `gain`.
nonisolated final class AppAudioTap: @unchecked Sendable {
    let processObjectIDs: [AudioObjectID]
    let gain: AudioGain

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.ahmetbugraozcan.screenshotapp.appvolume", qos: .userInteractive)

    init?(processObjectIDs: [AudioObjectID], outputUID: String, gain: Float) {
        self.processObjectIDs = processObjectIDs
        self.gain = AudioGain(gain)

        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs.map { NSNumber(value: $0) })
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        description.name = "DeskCast volume"

        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return nil }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "DeskCast Volume",
            kAudioAggregateDeviceUIDKey: "com.ahmetbugraozcan.deskcast.volume.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString
            ]]
        ]

        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        let gainBox = self.gain
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, inputData, _, outputData, _ in
            Self.render(input: inputData, output: outputData, gain: gainBox.value)
        }

        guard status == noErr, let ioProcID, AudioDeviceStart(aggregateID, ioProcID) == noErr else {
            stop()
            return nil
        }
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit {
        stop()
    }

    /// Copies the tapped interleaved Float32 stream to the output with gain,
    /// mapping channels onto interleaved or per-channel output buffers.
    private static func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        gain: Float
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)

        for outputIndex in 0..<outputs.count {
            let outBuffer = outputs[outputIndex]
            guard let outData = outBuffer.mData?.assumingMemoryBound(to: Float.self) else { continue }

            let outChannels = Int(max(outBuffer.mNumberChannels, 1))
            let outFrames = Int(outBuffer.mDataByteSize) / MemoryLayout<Float>.size / outChannels

            guard !inputs.isEmpty else {
                memset(outData, 0, Int(outBuffer.mDataByteSize))
                continue
            }

            // The tap's stereo stream comes after any input streams of the
            // output device itself (e.g. a headset mic), so read the last one.
            let inBuffer = inputs[inputs.count - 1]

            guard let inData = inBuffer.mData?.assumingMemoryBound(to: Float.self) else {
                memset(outData, 0, Int(outBuffer.mDataByteSize))
                continue
            }

            let inChannels = Int(max(inBuffer.mNumberChannels, 1))
            let inFrames = Int(inBuffer.mDataByteSize) / MemoryLayout<Float>.size / inChannels
            let frames = min(outFrames, inFrames)

            for frame in 0..<frames {
                for channel in 0..<outChannels {
                    let inChannel = min(channel + outputIndex * outChannels, inChannels - 1)
                    outData[frame * outChannels + channel] = inData[frame * inChannels + inChannel] * gain
                }
            }

            if frames < outFrames {
                memset(outData + frames * outChannels, 0, (outFrames - frames) * outChannels * MemoryLayout<Float>.size)
            }
        }
    }
}
