import AppKit
import Combine
import KeyboardShortcuts

/// Receives finished captures; the screenshot shelf in the app.
@MainActor
protocol CapturedImageReceiving: AnyObject {
    func addCapturedImage(_ image: NSImage)
}

/// Where the scrolling capture happens: a display and an area on it.
struct ScrollingCaptureArea: Equatable {
    let displayID: CGDirectDisplayID
    /// Global Cocoa frame of the display.
    let displayFrame: CGRect
    let scale: CGFloat
    /// Display-local, points, top-left origin.
    let rect: CGRect
}

@MainActor
protocol ScrollingCapturePresenting: AnyObject {
    /// Asks for an area on the display under the pointer; nil when cancelled.
    func selectArea(completion: @escaping (ScrollingCaptureArea?) -> Void)
    func showCaptureControls(for area: ScrollingCaptureArea)
    func hideCaptureControls()
}

/// Scrolling capture: the user picks an area and scrolls it; frames are
/// captured a few times a second and stitched into one tall image.
@MainActor
final class ScrollingCaptureViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case selecting
        case capturing
        case finishing
    }

    enum Status: Equatable {
        case waitingForScroll
        case scrolling
        case lostTrack
        case reachedLimit
    }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var status = Status.waitingForScroll
    /// Height of the stitched image so far, in points.
    @Published private(set) var capturedHeight: CGFloat = 0

    weak var presenter: ScrollingCapturePresenting?

    private let capturer: ScrollingFrameCapturing
    private let shelf: CapturedImageReceiving
    private let settings: ToolboxSettingsReading
    private let screenRecording: ScreenRecordingChecking
    private let toastPresenter: ToastPresenting
    private var captureTask: Task<Void, Never>?
    /// Identifies the running capture so a cancelled one can't touch the next.
    private var session = UUID()

    static let frameInterval: Duration = .milliseconds(120)

    init(
        capturer: ScrollingFrameCapturing,
        shelf: CapturedImageReceiving,
        settings: ToolboxSettingsReading,
        screenRecording: ScreenRecordingChecking,
        toastPresenter: ToastPresenting
    ) {
        self.capturer = capturer
        self.shelf = shelf
        self.settings = settings
        self.screenRecording = screenRecording
        self.toastPresenter = toastPresenter

        KeyboardShortcuts.onKeyUp(for: .scrollingCapture) { [weak self] in
            Task { @MainActor in self?.start() }
        }
    }

    var isBusy: Bool { phase != .idle }

    func start() {
        guard settings.isToolEnabled(.scrollingCapture), phase == .idle else { return }
        guard screenRecording.ensureAccess() else {
            PermissionAlertPresenter.showScreenRecordingHelp { [screenRecording] in
                screenRecording.openSettings()
            }
            return
        }

        phase = .selecting
        presenter?.selectArea { [weak self] area in
            guard let self else { return }
            guard let area else {
                phase = .idle
                return
            }
            begin(in: area)
        }
    }

    /// Stops capturing and adds what was stitched to the shelf.
    func finish() {
        guard phase == .capturing else { return }
        phase = .finishing
        captureTask?.cancel()
    }

    func cancel() {
        session = UUID()
        captureTask?.cancel()
        captureTask = nil
        reset()
    }

    private func begin(in area: ScrollingCaptureArea) {
        let session = UUID()
        self.session = session
        phase = .capturing
        status = .waitingForScroll
        capturedHeight = area.rect.height
        presenter?.showCaptureControls(for: area)

        let capturer = capturer
        captureTask = Task { [weak self] in
            do {
                let source = try await capturer.makeSource(displayID: area.displayID, rect: area.rect, scale: area.scale)
                let stitcher = try await Self.capture(from: source, scale: area.scale) { [weak self] status, height in
                    guard self?.session == session else { return }
                    self?.status = status
                    self?.capturedHeight = height
                }
                guard self?.session == session else { return }
                self?.deliver(stitcher, scale: area.scale)
            } catch {
                guard self?.session == session else { return }
                self?.fail()
            }
        }
    }

    /// Captures until cancelled (Done) or the height limit, stitching off the
    /// main actor.
    nonisolated private static func capture(
        from source: ScrollingFrameSource,
        scale: CGFloat,
        update: @escaping @MainActor (Status, CGFloat) -> Void
    ) async throws -> ScrollStitcher? {
        let first = try await source.captureFrame()
        guard var stitcher = ScrollStitcher(firstFrame: first) else { return nil }

        while !Task.isCancelled {
            try? await Task.sleep(for: frameInterval)
            guard !Task.isCancelled, let frame = try? await source.captureFrame() else { continue }

            let status: Status
            switch stitcher.add(frame) {
            case .appended: status = .scrolling
            case .unchanged: status = stitcher.height > stitcher.frameHeight ? .scrolling : .waitingForScroll
            case .lostTrack: status = .lostTrack
            case .reachedLimit: status = .reachedLimit
            }
            let height = CGFloat(stitcher.height) / scale
            await update(status, height)
            if status == .reachedLimit { break }
        }
        return stitcher
    }

    private func deliver(_ stitcher: ScrollStitcher?, scale: CGFloat) {
        // Cancel (not Done) also ends the loop; only Done or the limit keep the result.
        guard phase == .finishing || status == .reachedLimit else {
            reset()
            return
        }
        guard let stitcher, let image = stitcher.makeImage() else {
            fail()
            return
        }

        shelf.addCapturedImage(NSImage(
            cgImage: image,
            size: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        ))
        toastPresenter.show(
            AppLocalization.formatted("scrollCapture.done", Int(CGFloat(image.height) / scale)),
            systemImage: "scroll"
        )
        reset()
    }

    private func fail() {
        reset()
        NSSound.beep()
        toastPresenter.show(AppLocalization.string("scrollCapture.failed"), systemImage: "exclamationmark.triangle.fill")
    }

    private func reset() {
        presenter?.hideCaptureControls()
        phase = .idle
        status = .waitingForScroll
        capturedHeight = 0
    }
}

#if DEBUG
import UniformTypeIdentifiers

extension ScrollingCaptureViewModel {
    /// Debug builds only: `-DeskCastDemoScrollFrame <png path>` captures one
    /// frame of the area x 100, y 100, 600 × 400 pt on the main display through
    /// the scrolling-capture source, to check coordinates and scale.
    func writeDemoFrameIfRequested() async {
        guard let path = UserDefaults.standard.string(forKey: "DeskCastDemoScrollFrame"),
              let screen = NSScreen.screens.first,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let source = try? await capturer.makeSource(
                displayID: displayID, rect: CGRect(x: 100, y: 100, width: 600, height: 400), scale: screen.backingScaleFactor
              ),
              let frame = try? await source.captureFrame(),
              let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(output, frame, nil)
        CGImageDestinationFinalize(output)
    }
}
#endif
