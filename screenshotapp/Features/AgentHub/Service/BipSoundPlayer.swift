import AVFoundation

/// Bip's voice: short chiptune beeps synthesized at launch (no sound files).
/// Each sound is a few notes of a soft square/sine blend with quick fades.
@MainActor
final class BipSoundPlayer {
    enum Sound: CaseIterable {
        case open
        case close
        case poke
        case dizzy
        case approval
        case question
        case finished
        case error
        case send
        case received
        case attach
    }

    static let shared = BipSoundPlayer()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var isPrepared = false

    private init() {}

    func play(_ sound: Sound) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AgentHubSettings.Keys.soundsEnabled) else { return }
        let volume = Float(AgentHubSettings.soundVolume(in: defaults))
        guard volume > 0 else { return }

        prepareIfNeeded()
        guard isPrepared, let buffer = buffers[sound], !players.isEmpty else { return }

        if !engine.isRunning {
            try? engine.start()
        }

        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil)
        player.play()
        scheduleIdleStop()
    }

    private var idleStopTask: Task<Void, Never>?

    /// The engine keeps the audio hardware awake; stop it when quiet.
    private func scheduleIdleStop() {
        idleStopTask?.cancel()
        idleStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.engine.stop()
        }
    }

    private func prepareIfNeeded() {
        guard !isPrepared, let format else { return }

        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }

        for sound in Sound.allCases {
            buffers[sound] = Self.render(Self.notes(for: sound), format: format)
        }
        isPrepared = true
    }

    /// A note: frequency (Hz, 0 = rest), length (s), and an optional glide target.
    private struct Note {
        var frequency: Double
        var duration: Double
        var glideTo: Double?
        var gain = 1.0
    }

    private static func notes(for sound: Sound) -> [Note] {
        switch sound {
        case .open:
            [Note(frequency: 660, duration: 0.06), Note(frequency: 990, duration: 0.08)]
        case .close:
            [Note(frequency: 880, duration: 0.06), Note(frequency: 587, duration: 0.08)]
        case .poke:
            [Note(frequency: 520, duration: 0.07, glideTo: 380, gain: 0.9)]
        case .dizzy:
            (0..<6).map { index in Note(frequency: index.isMultiple(of: 2) ? 740 : 620, duration: 0.06, gain: 0.8) }
        case .approval:
            [Note(frequency: 784, duration: 0.09), Note(frequency: 0, duration: 0.05), Note(frequency: 1046, duration: 0.12)]
        case .question:
            [Note(frequency: 600, duration: 0.16, glideTo: 940)]
        case .finished:
            [Note(frequency: 523, duration: 0.07), Note(frequency: 659, duration: 0.07),
             Note(frequency: 784, duration: 0.07), Note(frequency: 1046, duration: 0.16)]
        case .error:
            [Note(frequency: 330, duration: 0.12, glideTo: 260), Note(frequency: 0, duration: 0.04), Note(frequency: 247, duration: 0.16)]
        case .send:
            [Note(frequency: 500, duration: 0.12, glideTo: 1200, gain: 0.8)]
        case .received:
            [Note(frequency: 988, duration: 0.06), Note(frequency: 1318, duration: 0.1)]
        case .attach:
            [Note(frequency: 440, duration: 0.05), Note(frequency: 554, duration: 0.05), Note(frequency: 880, duration: 0.1)]
        }
    }

    private static func render(_ notes: [Note], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let total = notes.reduce(0) { $0 + Int($1.duration * rate) }
        guard total > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(total)

        var index = 0
        var phase = 0.0
        for note in notes {
            let count = Int(note.duration * rate)
            let fade = min(Int(0.008 * rate), count / 2)
            for frame in 0..<count {
                let progress = Double(frame) / Double(max(count - 1, 1))
                let frequency = note.glideTo.map { note.frequency + ($0 - note.frequency) * progress } ?? note.frequency
                phase += 2 * .pi * frequency / rate
                // Mostly sine with a little square: soft but clearly "electronic".
                let sine = sin(phase)
                let square: Double = sine >= 0 ? 1 : -1
                var sample = note.frequency > 0 ? (0.78 * sine + 0.22 * square) : 0
                let envelope = min(Double(frame) / Double(max(fade, 1)), Double(count - frame) / Double(max(fade, 1)), 1)
                sample *= envelope * 0.32 * note.gain * (1 - progress * 0.25)
                channel[index] = Float(sample)
                index += 1
            }
        }
        return buffer
    }
}
