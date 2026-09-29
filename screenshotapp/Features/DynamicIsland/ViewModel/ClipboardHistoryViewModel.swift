import AppKit
import Combine

/// Recent pasteboard items for the island's Clipboard panel. Records only
/// while the island is on and the panel isn't hidden. Entries live in memory
/// and are forgotten when recording stops, unless the user opted in to saving
/// the history: then text, links and file references (never images) are kept
/// on disk and reloaded, and turning the option off deletes that file.
@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var isRecording = false
    @Published private(set) var savesHistory = false
    @Published var query = ""
    /// Set by the panel's search field; the island stays open while it's focused.
    @Published var isSearchFocused = false

    /// Hands keyboard focus back to the app being pasted into; set by the island panel.
    var releaseKeyboardFocus: (() -> Void)?

    private let clipboard: ClipboardAccessing
    private let store: ClipboardHistoryPersisting
    private var timer: Timer?
    private var lastChangeCount = 0
    private var settingsObserver: AnyCancellable?
    private var hasAppliedSaveSetting = false

    static let maxEntries = 30
    static let maxSavedEntries = 200
    /// Images can be large; keep fewer of them than text entries.
    static let maxImageEntries = 8
    private static let pollInterval: TimeInterval = 0.6

    init(clipboard: ClipboardAccessing? = nil, store: ClipboardHistoryPersisting? = nil) {
        self.clipboard = clipboard ?? ClipboardHistoryService()
        self.store = store ?? ClipboardHistoryFileStore()
    }

    var entryLimit: Int { savesHistory ? Self.maxSavedEntries : Self.maxEntries }

    /// Entries matching the search, newest first.
    var visibleEntries: [ClipboardEntry] {
        entries.filter { Self.entry($0, matches: query) }
    }

    /// Case- and diacritic-insensitive match on text, link or file names.
    static func entry(_ entry: ClipboardEntry, matches query: String) -> Bool {
        let query = searchKey(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return true }

        switch entry.content {
        case .text(let text):
            return searchKey(text).contains(query)
        case .url(let url):
            return searchKey(url.absoluteString).contains(query)
        case .files(let urls):
            return urls.contains { searchKey($0.lastPathComponent).contains(query) }
        case .image:
            return false
        }
    }

    /// Folds case and accents, and Turkish dotless ı to i, so "toplanti"
    /// finds "Toplantı" when typed on a keyboard without Turkish letters.
    private static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// Follows the island's on/off state, whether the panel is visible, and
    /// the save-history setting.
    func bind(to island: DynamicIslandViewModel) {
        settingsObserver = island.$isEnabled
            .combineLatest(island.$preferences)
            .map { isEnabled, preferences in
                (isEnabled && preferences.visiblePanels.contains(.clipboard), preferences.savesClipboardHistory)
            }
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] shouldRecord, saves in
                self?.setSavesHistory(saves)
                self?.setRecording(shouldRecord)
            }
    }

    func setSavesHistory(_ saves: Bool) {
        defer { hasAppliedSaveSetting = true }
        guard saves != savesHistory else {
            // Saving may have been turned off while DeskCast wasn't running.
            if !saves, !hasAppliedSaveSetting { store.erase() }
            return
        }
        savesHistory = saves

        if saves {
            // Keep what's already there, merged with anything saved earlier.
            let saved = store.load()
            entries += saved.filter { old in !entries.contains { $0.content == old.content } }
            trim()
            store.save(entries)
        } else {
            store.erase()
            trim()
        }
    }

    func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        timer?.invalidate()
        timer = nil

        guard recording else {
            entries = []
            query = ""
            return
        }

        if savesHistory {
            entries = store.load()
            trim()
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

        // After searching, the island holds keyboard focus; give it back so
        // ⌘V reaches the app the user was typing in.
        let hadFocus = isSearchFocused
        isSearchFocused = false
        releaseKeyboardFocus?()

        Task {
            try? await Task.sleep(for: .milliseconds(hadFocus ? 150 : 60))
            Self.postCommandV()
        }
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clear() {
        entries = []
        query = ""
        if savesHistory { store.erase() }
    }

    private func insert(_ entry: ClipboardEntry) {
        entries.removeAll { $0.content == entry.content }
        entries.insert(entry, at: 0)
        trim()
        persist()
    }

    private func persist() {
        guard savesHistory else { return }
        store.save(entries)
    }

    private func trim() {
        if entries.count > entryLimit {
            entries.removeLast(entries.count - entryLimit)
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
