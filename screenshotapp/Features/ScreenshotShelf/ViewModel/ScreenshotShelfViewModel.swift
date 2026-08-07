import AppKit
import Combine
import KeyboardShortcuts

@MainActor
final class ScreenshotShelfViewModel: ObservableObject, VideoShelfCollecting {
    @Published private(set) var screenshots: [ScreenshotItem] = []
    @Published private(set) var isCapturing = false

    private var defaultsObserver: AnyCancellable?
    private var expirationTimers: [UUID: DispatchWorkItem] = [:]
    private var expirationTimerTokens: [UUID: UUID] = [:]
    private var autoHideConfiguration: AutoHideConfiguration?
    weak var presenter: ScreenshotShelfPresenting?
    private let shelfCollector: ShelfCollecting
    private let capturer: ScreenshotCapturing
    private let recognizer: TextRecognizing
    private let exporter: ScreenshotExporting
    private let finderPath: FinderPathProviding
    private let videoMetadata: VideoMetadataLoading
    private let settings: ScreenshotShelfSettingsReading & ToolboxSettingsReading
    private let toastPresenter: ToastPresenting
    private let screenRecording: ScreenRecordingChecking

    init(
        shelfCollector: ShelfCollecting,
        capturer: ScreenshotCapturing,
        recognizer: TextRecognizing,
        exporter: ScreenshotExporting,
        finderPath: FinderPathProviding,
        videoMetadata: VideoMetadataLoading,
        settings: ScreenshotShelfSettingsReading & ToolboxSettingsReading,
        toastPresenter: ToastPresenting,
        screenRecording: ScreenRecordingChecking
    ) {
        self.shelfCollector = shelfCollector
        self.capturer = capturer
        self.recognizer = recognizer
        self.exporter = exporter
        self.finderPath = finderPath
        self.videoMetadata = videoMetadata
        self.settings = settings
        self.toastPresenter = toastPresenter
        self.screenRecording = screenRecording
        autoHideConfiguration = AutoHideConfiguration(settings: settings.screenshotShelfSettings())
        defaultsObserver = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.applySettingsChange()
            }
        }

        KeyboardShortcuts.removeHandler(for: .captureSelectedArea)
        KeyboardShortcuts.onKeyUp(for: .captureSelectedArea) { [weak self] in
            Task { @MainActor in
                self?.captureSelectedArea()
            }
        }
    }

    deinit {
        KeyboardShortcuts.removeHandler(for: .captureSelectedArea)
        expirationTimers.values.forEach { $0.cancel() }
    }

    func captureSelectedArea() {
        guard settings.isToolEnabled(.captureSelectedArea) else { return }
        guard !isCapturing else { return }
        guard screenRecording.ensureAccess() else {
            showScreenRecordingPermissionHelp()
            return
        }

        isCapturing = true
        let settings = settings.screenshotShelfSettings()
        let screenAnchor = presenter?.screenAnchorForNewCapture(settings: settings)
        capturer.captureSelectedArea(
            preserveClipboard: !settings.copyCapturedScreenshotToClipboard
        ) { [weak self] result in
            guard let self else { return }

            isCapturing = false

            switch result {
            case .success(let image):
                add(image, screenAnchor: screenAnchor)
            case .failure(let error):
                handleCaptureFailure(error)
            }
        }
    }

    func captureOCRTextFromSelectedArea() {
        guard settings.isToolEnabled(.captureOCR) else { return }
        guard !isCapturing else { return }
        guard screenRecording.ensureAccess() else {
            showScreenRecordingPermissionHelp()
            return
        }

        isCapturing = true
        capturer.captureSelectedArea(preserveClipboard: true) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let image):
                recognizeAndCopyText(from: image)
            case .failure(let error):
                isCapturing = false
                handleCaptureFailure(error)
            }
        }
    }

    func remove(_ item: ScreenshotItem) {
        removeScreenshot(withID: item.id)
    }

    func copy(_ item: ScreenshotItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if item.isVideo, let fileURL = item.fileURL {
            pasteboard.writeObjects([fileURL as NSURL])
        } else {
            pasteboard.writeObjects([item.image])
        }
    }

    func copyAll() {
        guard !screenshots.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let writers: [NSPasteboardWriting] = screenshots.compactMap { item in
            if item.isVideo, let fileURL = item.fileURL {
                return fileURL as NSURL
            }

            return item.image
        }

        guard pasteboard.writeObjects(writers) else {
            NSSound.beep()
            return
        }
    }

    func clearAll() {
        guard !screenshots.isEmpty else {
            return
        }

        cancelAllExpirationTimers()
        screenshots.removeAll()
        presenter?.refresh()
    }

    func copyFrontFinderPath() {
        guard settings.isToolEnabled(.copyFinderPath) else { return }

        do {
            let path = try finderPath.frontFinderWindowPath()
            copyPathToPasteboard(path)
        } catch FinderPathService.FinderPathError.noOpenFinderWindow {
            NSSound.beep()
            showToast(AppLocalization.string("No Finder window open"), systemImage: "exclamationmark.triangle.fill")
        } catch FinderPathService.FinderPathError.automationDenied {
            NSSound.beep()
            showToast(AppLocalization.string("Allow Finder access"), systemImage: "exclamationmark.triangle.fill")
        } catch FinderPathService.FinderPathError.noFolderPath {
            NSSound.beep()
            showToast(
                AppLocalization.string("This Finder window has no folder path (e.g. Recents or Search)."),
                systemImage: "questionmark.folder"
            )
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not copy path"), systemImage: "exclamationmark.triangle.fill")
        }
    }

    func copyRecognizedText(_ item: ScreenshotItem) {
        guard !item.isVideo else { return }

        recognizer.recognizeText(in: item.image) { result in
            switch result {
            case .success(let text):
                self.copyTextToPasteboard(text)
            case .failure(let error):
                self.handleOCRFailure(error)
            }
        }
    }

    func addToShelf(_ item: ScreenshotItem) {
        if item.isVideo, let fileURL = item.fileURL {
            shelfCollector.addFile(fileURL)
        } else {
            let name = ScreenshotExportNaming.timestampedFilename(for: item.createdAt)
            shelfCollector.addScreenshot(item.image, name: name)
        }
    }

    func showInFinder(_ item: ScreenshotItem) {
        if let url = currentFileURL(for: item.id),
           FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        // Not saved yet (or the file moved) — persist it, then reveal it.
        guard let url = saveToConfiguredDirectory(
            item,
            suggestedFilename: ScreenshotExportNaming.timestampedFilename(for: item.createdAt),
            failureMessage: AppLocalization.string("Could not save image")
        ) else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func draggingPasteboardWriter(for item: ScreenshotItem) -> NSPasteboardWriting? {
        if item.isVideo, let fileURL = item.fileURL {
            return fileURL as NSURL
        }

        do {
            let url = try TemporaryPNGWriter.write(item.image)
            return url as NSURL
        } catch {
            NSSound.beep()
            return nil
        }
    }

    func saveAs(_ item: ScreenshotItem) {
        guard !item.isVideo else { return }

        saveWithPanel(
            item,
            suggestedFilename: ScreenshotExportNaming.timestampedFilename(for: item.createdAt)
        )
    }

    func quickSave(_ item: ScreenshotItem) {
        guard !item.isVideo else { return }

        saveToConfiguredDirectory(
            item,
            suggestedFilename: ScreenshotExportNaming.timestampedFilename(for: item.createdAt),
            failureMessage: AppLocalization.string("Could not quick save image")
        )
    }

    func save(_ item: ScreenshotItem, exportOption: ScreenshotExportOption) {
        guard !item.isVideo else { return }

        saveToConfiguredDirectory(
            item,
            suggestedFilename: exportOption.filename,
            failureMessage: AppLocalization.string("Could not save image")
        )
    }

    func openInPreview(_ item: ScreenshotItem) {
        if item.isVideo, let fileURL = item.fileURL {
            NSWorkspace.shared.open(fileURL)
            return
        }

        do {
            let url = try TemporaryPNGWriter.write(item.image)
            let configuration = NSWorkspace.OpenConfiguration()
            let previewURL = URL(fileURLWithPath: "/System/Applications/Preview.app")

            NSWorkspace.shared.open(
                [url],
                withApplicationAt: previewURL,
                configuration: configuration
            )
        } catch {
            NSSound.beep()
        }
    }

    func togglePin(_ item: ScreenshotItem) {
        guard let index = screenshots.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        var updatedScreenshots = screenshots
        let wasPinned = updatedScreenshots[index].isPinned
        updatedScreenshots[index].isPinned.toggle()
        let updatedItem = updatedScreenshots[index]
        screenshots = updatedScreenshots
        presenter?.refresh()

        if updatedItem.isPinned {
            cancelExpirationTimer(for: updatedItem.id)
        } else if wasPinned {
            startExpirationTimerIfNeeded(for: updatedItem)
        }
    }

    func addVideo(at url: URL) {
        let settings = settings.screenshotShelfSettings()
        let screenAnchor = presenter?.screenAnchorForNewCapture(settings: settings)

        videoMetadata.loadMetadata(for: url) { [weak self] result in
            guard let self else { return }

            let metadata: VideoMetadata
            switch result {
            case .success(let loadedMetadata):
                metadata = loadedMetadata
            case .failure:
                metadata = VideoMetadata(
                    thumbnail: NSWorkspace.shared.icon(forFile: url.path),
                    durationSeconds: nil
                )
            }

            let item = ScreenshotItem(
                videoThumbnail: metadata.thumbnail,
                durationSeconds: metadata.durationSeconds,
                fileURL: url,
                isPinned: settings.pinScreenshotsByDefault
            )
            screenshots.insert(item, at: 0)
            cancelExpirationTimers(for: trimToMaxStackCount(settings.maxStackCount))
            presenter?.refresh(screenAnchor: screenAnchor)
            startExpirationTimerIfNeeded(for: item, settings: settings)
        }
    }

    func moveScreenshot(withID draggedID: UUID, toDestinationIndex destinationIndex: Int) {
        guard canMoveScreenshot(withID: draggedID, toDestinationIndex: destinationIndex),
              let sourceIndex = screenshots.firstIndex(where: { $0.id == draggedID }) else {
            return
        }

        let item = screenshots.remove(at: sourceIndex)
        let clampedDestinationIndex = min(max(destinationIndex, 0), screenshots.count)
        screenshots.insert(item, at: clampedDestinationIndex)
        presenter?.refresh()
    }

    func canMoveScreenshot(withID draggedID: UUID, toDestinationIndex destinationIndex: Int) -> Bool {
        guard let sourceIndex = screenshots.firstIndex(where: { $0.id == draggedID }) else {
            return false
        }

        let clampedDestinationIndex = min(max(destinationIndex, 0), screenshots.count - 1)
        return clampedDestinationIndex != sourceIndex
    }

    private func saveWithPanel(_ item: ScreenshotItem, suggestedFilename: String) {
        do {
            guard let url = try exporter.save(
                item.image,
                suggestedFilename: suggestedFilename
            ) else {
                return
            }

            setFileURL(url, forID: item.id)
            showToast(AppLocalization.formatted("Saved %@", url.lastPathComponent))
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not save image"), systemImage: "exclamationmark.triangle.fill")
        }
    }

    @discardableResult
    private func saveToConfiguredDirectory(
        _ item: ScreenshotItem,
        suggestedFilename: String,
        failureMessage: String
    ) -> URL? {
        do {
            let settings = settings.screenshotShelfSettings()
            let url = try exporter.save(
                item.image,
                to: settings.saveDirectoryURL,
                suggestedFilename: suggestedFilename
            )
            setFileURL(url, forID: item.id)
            showToast(AppLocalization.formatted("Saved %@", url.lastPathComponent))
            return url
        } catch {
            NSSound.beep()
            showToast(failureMessage, systemImage: "exclamationmark.triangle.fill")
            return nil
        }
    }

    private func setFileURL(_ url: URL, forID id: UUID) {
        guard let index = screenshots.firstIndex(where: { $0.id == id }) else {
            return
        }

        screenshots[index].fileURL = url
    }

    private func currentFileURL(for id: UUID) -> URL? {
        screenshots.first(where: { $0.id == id })?.fileURL
    }

    private func add(_ image: NSImage, screenAnchor: ScreenshotShelfScreenAnchor?) {
        let settings = settings.screenshotShelfSettings()
        let item = ScreenshotItem(
            image: image,
            isPinned: settings.pinScreenshotsByDefault
        )

        screenshots.insert(item, at: 0)
        cancelExpirationTimers(for: trimToMaxStackCount(settings.maxStackCount))

        presenter?.refresh(screenAnchor: screenAnchor)
        startExpirationTimerIfNeeded(for: item, settings: settings)
        autoSaveIfNeeded(item, settings: settings)
    }

    private func autoSaveIfNeeded(
        _ item: ScreenshotItem,
        settings: ScreenshotShelfSettingsSnapshot
    ) {
        guard settings.autoSaveCapturedScreenshots else {
            return
        }

        saveToConfiguredDirectory(
            item,
            suggestedFilename: ScreenshotExportNaming.timestampedFilename(for: item.createdAt),
            failureMessage: AppLocalization.string("Could not auto-save image")
        )
    }

    private func recognizeAndCopyText(from image: NSImage) {
        recognizer.recognizeText(in: image) { [weak self] result in
            guard let self else { return }

            isCapturing = false

            switch result {
            case .success(let text):
                copyTextToPasteboard(text)
            case .failure(let error):
                handleOCRFailure(error)
            }
        }
    }

    private func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            NSSound.beep()
            showToast(AppLocalization.string("Could not copy text"), systemImage: "exclamationmark.triangle.fill")
            return
        }

        showToast(AppLocalization.string("Copied to clipboard"))
    }

    private func copyPathToPasteboard(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard pasteboard.setString(path, forType: .string) else {
            NSSound.beep()
            showToast(AppLocalization.string("Could not copy path"), systemImage: "exclamationmark.triangle.fill")
            return
        }

        showToast(AppLocalization.string("Path copied"))
    }

    private func handleOCRFailure(_ error: Error) {
        NSSound.beep()

        if let recognitionError = error as? OCRTextRecognitionError {
            switch recognitionError {
            case .noTextFound:
                showToast(AppLocalization.string("No text found"), systemImage: "exclamationmark.triangle.fill")
            case .imageConversionFailed:
                showToast(AppLocalization.string("Could not read image"), systemImage: "exclamationmark.triangle.fill")
            }
        } else {
            showToast(AppLocalization.string("OCR failed"), systemImage: "exclamationmark.triangle.fill")
        }
    }

    func showToast(_ message: String, systemImage: String = "checkmark.circle.fill") {
        toastPresenter.show(message, systemImage: systemImage)
    }

    private func trimToMaxStackCount(_ maxStackCount: Int) -> [UUID] {
        // When overflow scrolling is enabled the shelf keeps every item and lets
        // the floating panel scroll; only the visible window is capped (in the
        // panel coordinator), so nothing is removed here.
        guard !settings.screenshotShelfSettings().scrollBeyondMaxStack else {
            return []
        }

        guard screenshots.count > maxStackCount else {
            return []
        }

        let overflowCount = screenshots.count - maxStackCount
        let removedIDs = screenshots.suffix(overflowCount).map(\.id)
        screenshots.removeLast(overflowCount)

        return removedIDs
    }

    private func applySettingsChange() {
        let settings = settings.screenshotShelfSettings()
        cancelExpirationTimers(for: trimToMaxStackCount(settings.maxStackCount))
        presenter?.refreshIfVisible()
        reconcileExpirationTimers(settings: settings)
    }

    private func handleCaptureFailure(_ error: ScreenshotCaptureError) {
        if case .cancelled = error {
            return
        }

        if error.isLikelyPermissionProblem || !screenRecording.hasAccess {
            showScreenRecordingPermissionHelp()
        } else {
            NSSound.beep()
        }
    }

    private func showScreenRecordingPermissionHelp() {
        PermissionAlertPresenter.showScreenRecordingHelp {
            screenRecording.openSettings()
        }
    }

    private func startExpirationTimerIfNeeded(for item: ScreenshotItem) {
        startExpirationTimerIfNeeded(for: item, settings: settings.screenshotShelfSettings())
    }

    private func startExpirationTimerIfNeeded(
        for item: ScreenshotItem,
        settings: ScreenshotShelfSettingsSnapshot
    ) {
        guard !item.isPinned, !settings.neverAutoHide else {
            return
        }

        cancelExpirationTimer(for: item.id)

        let itemID = item.id
        let timerToken = UUID()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.expireScreenshot(withID: itemID, timerToken: timerToken)
            }
        }

        expirationTimers[itemID] = workItem
        expirationTimerTokens[itemID] = timerToken
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .seconds(settings.previewDurationSeconds),
            execute: workItem
        )
    }

    private func expireScreenshot(withID itemID: UUID, timerToken: UUID) {
        guard expirationTimerTokens[itemID] == timerToken else {
            return
        }

        expirationTimers[itemID] = nil
        expirationTimerTokens[itemID] = nil

        guard let item = screenshots.first(where: { $0.id == itemID }) else {
            return
        }

        let settings = settings.screenshotShelfSettings()
        guard !settings.neverAutoHide, !item.isPinned else {
            return
        }

        screenshots.removeAll { $0.id == itemID }
        presenter?.refresh()
    }

    func removeScreenshot(withID itemID: UUID) {
        cancelExpirationTimer(for: itemID)

        let oldCount = screenshots.count
        screenshots.removeAll { $0.id == itemID }

        guard screenshots.count != oldCount else {
            return
        }

        presenter?.refresh()
    }

    private func reconcileExpirationTimers(settings: ScreenshotShelfSettingsSnapshot) {
        let configuration = AutoHideConfiguration(settings: settings)
        let configurationChanged = autoHideConfiguration != configuration
        autoHideConfiguration = configuration

        let currentIDs = Set(screenshots.map(\.id))
        let staleIDs = expirationTimers.keys.filter { !currentIDs.contains($0) }
        cancelExpirationTimers(for: staleIDs)

        if settings.neverAutoHide {
            cancelAllExpirationTimers()
            return
        }

        for item in screenshots {
            if item.isPinned {
                cancelExpirationTimer(for: item.id)
            } else if configurationChanged || expirationTimers[item.id] == nil {
                startExpirationTimerIfNeeded(for: item, settings: settings)
            }
        }
    }

    private func cancelExpirationTimer(for itemID: UUID) {
        expirationTimers[itemID]?.cancel()
        expirationTimers[itemID] = nil
        expirationTimerTokens[itemID] = nil
    }

    private func cancelExpirationTimers<S: Sequence>(for itemIDs: S) where S.Element == UUID {
        for itemID in itemIDs {
            cancelExpirationTimer(for: itemID)
        }
    }

    private func cancelAllExpirationTimers() {
        expirationTimers.values.forEach { $0.cancel() }
        expirationTimers.removeAll()
        expirationTimerTokens.removeAll()
    }
}

private struct AutoHideConfiguration: Equatable {
    let previewDurationSeconds: Int
    let neverAutoHide: Bool

    init(settings: ScreenshotShelfSettingsSnapshot) {
        previewDurationSeconds = settings.previewDurationSeconds
        neverAutoHide = settings.neverAutoHide
    }
}
