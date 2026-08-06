import AppKit
import AVFoundation
import Combine
import KeyboardShortcuts

@MainActor
final class ScreenRecordingViewModel: ObservableObject {
    @Published private(set) var availableDisplays: [ScreenRecordingDisplay] = []
    @Published private(set) var availableMicrophones: [ScreenRecordingMicrophone] = []
    @Published private(set) var selectedDisplayID: CGDirectDisplayID?
    @Published private(set) var selectedArea: CGRect?
    @Published private(set) var isPreparing = false
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var mode: ScreenRecordingMode
    @Published private(set) var capturesSystemAudio: Bool
    @Published private(set) var capturesMicrophone: Bool
    @Published private(set) var microphoneDeviceID: String
    @Published private(set) var showsCursor: Bool
    @Published private(set) var showsMouseClicks: Bool
    @Published private(set) var frameRate: ScreenRecordingFrameRate
    @Published private(set) var quality: ScreenRecordingQuality
    @Published private(set) var codec: ScreenRecordingCodec
    @Published private(set) var countdownSeconds: Int

    weak var presenter: ScreenRecordingPresenting?

    private let recorder: ScreenRecordingServicing
    private let sources: ScreenRecordingSourceProviding
    private let shelf: VideoShelfCollecting
    private let settings: ScreenRecordingSettingsReading & ToolboxSettingsReading
    private let toastPresenter: ToastPresenting
    private let screenRecording: ScreenRecordingChecking
    private var elapsedTimer: Timer?
    private var countdownTimer: Timer?
    private var countdownRemaining = 0
    private var pendingCountdownDisplay: ScreenRecordingDisplay?

    init(
        recorder: ScreenRecordingServicing,
        sources: ScreenRecordingSourceProviding,
        shelf: VideoShelfCollecting,
        settings: ScreenRecordingSettingsReading & ToolboxSettingsReading,
        toastPresenter: ToastPresenting,
        screenRecording: ScreenRecordingChecking
    ) {
        self.recorder = recorder
        self.sources = sources
        self.shelf = shelf
        self.settings = settings
        self.toastPresenter = toastPresenter
        self.screenRecording = screenRecording

        let snapshot = settings.screenRecordingSettings()
        mode = snapshot.defaultMode
        capturesSystemAudio = snapshot.capturesSystemAudio
        capturesMicrophone = snapshot.capturesMicrophone
        microphoneDeviceID = snapshot.microphoneDeviceID
        showsCursor = snapshot.showsCursor
        showsMouseClicks = snapshot.showsMouseClicks
        frameRate = snapshot.frameRate
        quality = snapshot.quality
        codec = snapshot.codec
        countdownSeconds = snapshot.countdownSeconds

        KeyboardShortcuts.removeHandler(for: .captureVideo)
        KeyboardShortcuts.onKeyUp(for: .captureVideo) { [weak self] in
            Task { @MainActor in
                self?.captureSelectedAreaVideo()
            }
        }
    }

    deinit {
        KeyboardShortcuts.removeHandler(for: .captureVideo)
        elapsedTimer?.invalidate()
        countdownTimer?.invalidate()
    }

    /// Kept as the menu/shortcut entry point. It now presents DeskCast's custom
    /// recorder instead of immediately launching a system command.
    func captureSelectedAreaVideo() {
        showRecorder()
    }

    func showRecorder() {
        guard settings.isToolEnabled(.captureVideo) else { return }
        refreshSources()
        presenter?.showControlPanel()
    }

    func hideRecorder() {
        guard !isRecording, !isPreparing else { return }
        presenter?.hideControlPanel()
    }

    func selectDisplay(_ id: CGDirectDisplayID) {
        guard selectedDisplayID != id else { return }
        selectedDisplayID = id
        selectedArea = nil
    }

    func setMode(_ newMode: ScreenRecordingMode) {
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: ScreenRecordingSettings.Keys.defaultMode)

        if newMode == .entireScreen {
            selectedArea = nil
        }
    }

    /// Switches to selected-area mode and immediately opens the selection overlay
    /// so the user can draw a region in one step. Called from the mode picker.
    func enterAreaMode() {
        setMode(.selectedArea)
        chooseSelectedArea()
    }

    func setCapturesSystemAudio(_ isEnabled: Bool) {
        capturesSystemAudio = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: ScreenRecordingSettings.Keys.capturesSystemAudio)
    }

    func setCapturesMicrophone(_ isEnabled: Bool) {
        capturesMicrophone = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: ScreenRecordingSettings.Keys.capturesMicrophone)
    }

    func setMicrophoneDeviceID(_ id: String) {
        microphoneDeviceID = id
        UserDefaults.standard.set(id, forKey: ScreenRecordingSettings.Keys.microphoneDeviceID)
    }

    func setShowsCursor(_ isEnabled: Bool) {
        showsCursor = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: ScreenRecordingSettings.Keys.showsCursor)
    }

    func setShowsMouseClicks(_ isEnabled: Bool) {
        showsMouseClicks = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: ScreenRecordingSettings.Keys.showsMouseClicks)
    }

    func setFrameRate(_ newFrameRate: ScreenRecordingFrameRate) {
        frameRate = newFrameRate
        UserDefaults.standard.set(newFrameRate.rawValue, forKey: ScreenRecordingSettings.Keys.frameRate)
    }

    func setQuality(_ newQuality: ScreenRecordingQuality) {
        quality = newQuality
        UserDefaults.standard.set(newQuality.rawValue, forKey: ScreenRecordingSettings.Keys.quality)
    }

    func setCodec(_ newCodec: ScreenRecordingCodec) {
        codec = newCodec
        UserDefaults.standard.set(newCodec.rawValue, forKey: ScreenRecordingSettings.Keys.codec)
    }

    func setCountdownSeconds(_ seconds: Int) {
        countdownSeconds = max(0, seconds)
        UserDefaults.standard.set(countdownSeconds, forKey: ScreenRecordingSettings.Keys.countdownSeconds)
    }

    func chooseSelectedArea() {
        guard let display = selectedDisplay else { return }

        presenter?.showSelectionOverlay(
            on: display,
            initialRect: selectedArea
        ) { [weak self] rect in
            guard let self, let rect else { return }
            selectedArea = rect
            setMode(.selectedArea)
        }
    }

    func startRecording() {
        guard !isPreparing, !isRecording, let display = selectedDisplay else { return }

        if mode == .selectedArea, selectedArea == nil {
            chooseSelectedArea()
            return
        }

        guard screenRecording.ensureAccess() else {
            showScreenRecordingPermissionHelp()
            return
        }

        isPreparing = true
        presenter?.refreshControlPanel()

        Task { @MainActor in
            if capturesMicrophone {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                guard granted else {
                    isPreparing = false
                    toastPresenter.show(
                        AppLocalization.string("Microphone access is required"),
                        style: .error
                    )
                    presenter?.refreshControlPanel()
                    return
                }
            }

            startCountdownThenCapture(on: display)
        }
    }

    private func startCountdownThenCapture(on display: ScreenRecordingDisplay) {
        guard countdownSeconds > 0 else {
            beginCapture(on: display)
            return
        }

        pendingCountdownDisplay = display
        countdownRemaining = countdownSeconds
        presenter?.showCountdown(countdownRemaining)

        countdownTimer?.invalidate()
        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(handleCountdownTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    @objc private func handleCountdownTick() {
        countdownRemaining -= 1
        if countdownRemaining <= 0 {
            countdownTimer?.invalidate()
            countdownTimer = nil
            presenter?.hideCountdown()
            if let display = pendingCountdownDisplay {
                pendingCountdownDisplay = nil
                beginCapture(on: display)
            }
        } else {
            presenter?.showCountdown(countdownRemaining)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isPreparing = true
        recorder.stop { [weak self] result in
            guard let self else { return }

            presenter?.hideRecordingIndicator()
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            elapsedSeconds = 0
            isRecording = false
            isPreparing = false

            switch result {
            case .success(let url):
                shelf.addVideo(at: url)
                toastPresenter.show(AppLocalization.formatted("Saved %@", url.lastPathComponent))
            case .failure(let error):
                handleRecordingFailure(error)
            }

            presenter?.refreshControlPanel()
        }
    }

    private var selectedDisplay: ScreenRecordingDisplay? {
        guard let selectedDisplayID else { return availableDisplays.first }
        return availableDisplays.first { $0.id == selectedDisplayID }
    }

    private func refreshSources() {
        availableDisplays = sources.availableDisplays()
        availableMicrophones = sources.availableMicrophones()

        if selectedDisplay == nil {
            selectedDisplayID = displayContainingMouse()?.id ?? availableDisplays.first?.id
        }

        if !microphoneDeviceID.isEmpty,
           !availableMicrophones.contains(where: { $0.id == microphoneDeviceID }) {
            microphoneDeviceID = ""
        }
    }

    private func displayContainingMouse() -> ScreenRecordingDisplay? {
        let location = NSEvent.mouseLocation
        return availableDisplays.first { $0.frame.contains(location) }
    }

    private func beginCapture(on display: ScreenRecordingDisplay) {
        let snapshot = settings.screenRecordingSettings()
        let filename = ScreenRecordingFilename.timestampedFilename(
            for: Date(),
            prefix: snapshot.filenamePrefix
        )
        let destinationURL = uniqueDestinationURL(
            in: snapshot.saveDirectoryURL,
            filename: filename
        )
        let selectedMicrophoneID: String? = capturesMicrophone
            ? (microphoneDeviceID.isEmpty ? nil : microphoneDeviceID)
            : nil
        let request = ScreenRecordingRequest(
            display: display,
            sourceRect: mode == .selectedArea ? selectedArea : nil,
            destinationURL: destinationURL,
            capturesSystemAudio: capturesSystemAudio,
            capturesMicrophone: capturesMicrophone,
            microphoneDeviceID: selectedMicrophoneID,
            showsCursor: showsCursor,
            showsMouseClicks: showsMouseClicks,
            frameRate: frameRate.rawValue,
            quality: quality,
            codec: codec
        )

        recorder.start(request) { [weak self] result in
            guard let self else { return }

            isPreparing = false
            switch result {
            case .success:
                isRecording = true
                startElapsedTimer()
                if mode == .selectedArea, let area = selectedArea {
                    presenter?.showRecordingIndicator(on: display, rect: area)
                }
            case .failure(let error):
                handleRecordingFailure(error)
            }
            presenter?.refreshControlPanel()
        }
    }

    private func uniqueDestinationURL(in directory: URL, filename: String) -> URL {
        let fileManager = FileManager.default
        let baseURL = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: baseURL.path) else { return baseURL }

        let stem = baseURL.deletingPathExtension().lastPathComponent
        let extensionName = baseURL.pathExtension
        for index in 2... {
            let candidate = directory.appendingPathComponent("\(stem)-\(index).\(extensionName)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return baseURL
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedSeconds = 0
        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(handleElapsedTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    @objc private func handleElapsedTimer() {
        elapsedSeconds += 1
    }

    private func handleRecordingFailure(_ error: ScreenRecordingServiceError) {
        presenter?.hideRecordingIndicator()
        NSSound.beep()
        toastPresenter.show(
            error.localizedDescription.isEmpty
                ? AppLocalization.string("Could not record video")
                : error.localizedDescription,
            style: .error
        )
    }

    private func showScreenRecordingPermissionHelp() {
        isPreparing = false
        PermissionAlertPresenter.showScreenRecordingHelp {
            screenRecording.openSettings()
        }
    }
}
