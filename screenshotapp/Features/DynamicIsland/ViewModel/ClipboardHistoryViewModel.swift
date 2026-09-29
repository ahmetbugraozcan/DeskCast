import AppKit
import Combine

/// Recent pasteboard items for the island's Clipboard panel. Records only
/// while the island is on and the panel isn't hidden, keeps entries in memory,
/// and forgets them when recording stops.
@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var isRecording = false

    private let clipboard: ClipboardAccessing
    private var timer: Timer?
    private var lastChangeCount = 0
    private var settingsObserver: AnyCancellable?

    static let maxEntries = 30
    /// Images can be large; keep fewer of them than text entries.
    static let maxImageEntries = 8
    private static let pollInterval: TimeInterval = 0.6

    init(clipboard: ClipboardAccessing? = nil) {
        self.clipboard = clipboard ?? ClipboardHistoryService()
    }

    /// Follows the island's on/off state and whether the panel is visible.
    func bind(to island: DynamicIslandViewModel) {
        settingsObserver = island.$isEnabled
            .combineLatest(island.$preferences)
            .map { isEnabled, preferences in isEnabled && preferences.visiblePanels.contains(.clipboard) }
            .removeDuplicates()
            .sink { [weak self] shouldRecord in
                self?.setRecording(shouldRecord)
            }
    }

    func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        timer?.invalidate()
        timer = nil

        guard recording else {
            entries = []
            return
        }

        // Start with whatever is on the clipboard now.
        lastChangeCount = clipboard.changeCount
        if let entry = clipboard.currentEntry() {
            insert(entry)
        }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func poll() {
        guard isRecording else { return }

        let changeCount = clipboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if let entry = clipboard.currentEntry() {
            insert(entry)
        }
    }

    /// Puts the entry back on the clipboard and moves it to the top.
    func copy(_ entry: ClipboardEntry) {
        lastChangeCount = clipboard.write(entry)
        insert(ClipboardEntry(content: entry.content, copiedAt: Date(), sourceBundleIdentifier: entry.sourceBundleIdentifier))
    }

    /// Copies the entry and pastes it into the frontmost app. The island never
    /// takes focus, so ⌘V lands where the user was typing. Needs Accessibility;
    /// without it the entry is only copied.
    func paste(_ entry: ClipboardEntry) {
        copy(entry)

        guard AXIsProcessTrusted() else { return }

        Task {
            try? await Task.sleep(for: .milliseconds(60))
            Self.postCommandV()
        }
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        entries = []
    }

    private func insert(_ entry: ClipboardEntry) {
        entries.removeAll { $0.content == entry.content }
        entries.insert(entry, at: 0)

        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }

        let imageIDs = entries.filter(\.isImage).map(\.id)
        if imageIDs.count > Self.maxImageEntries {
            let dropped = Set(imageIDs.suffix(imageIDs.count - Self.maxImageEntries))
            entries.removeAll { dropped.contains($0.id) }
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 9

        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
