import AppKit
import Testing
@testable import screenshotapp

@MainActor
private final class SpyClipboard: ClipboardAccessing {
    var changeCount = 0
    var current: ClipboardEntry?

    func currentEntry() -> ClipboardEntry? { current }

    func write(_ entry: ClipboardEntry) -> Int {
        current = entry
        changeCount += 1
        return changeCount
    }

    func copy(_ content: ClipboardEntry.Content) {
        current = ClipboardEntry(content: content, copiedAt: Date(), sourceBundleIdentifier: nil)
        changeCount += 1
    }
}

@MainActor
private final class MemoryStore: ClipboardHistoryPersisting {
    var saved: [ClipboardEntry] = []
    private(set) var eraseCount = 0

    func load() -> [ClipboardEntry] { saved }
    func save(_ entries: [ClipboardEntry]) { saved = entries.filter { !$0.isImage } }
    func erase() {
        saved = []
        eraseCount += 1
    }
}

@MainActor
struct ClipboardHistoryPersistenceTests {
    private func record(_ texts: [String], clipboard: SpyClipboard, model: ClipboardHistoryViewModel) {
        for text in texts {
            clipboard.copy(.text(text))
            model.poll()
        }
    }

    @Test func memoryOnlyByDefault() {
        let store = MemoryStore()
        let clipboard = SpyClipboard()
        let model = ClipboardHistoryViewModel(clipboard: clipboard, store: store)
        model.setRecording(true)
        record(["a", "b"], clipboard: clipboard, model: model)

        #expect(store.saved.isEmpty)
        model.setRecording(false)
        #expect(model.entries.isEmpty)
    }

    @Test func savedHistorySurvivesRecordingRestart() {
        let store = MemoryStore()
        let clipboard = SpyClipboard()
        let model = ClipboardHistoryViewModel(clipboard: clipboard, store: store)
        model.setSavesHistory(true)
        model.setRecording(true)
        record(["one", "two"], clipboard: clipboard, model: model)
        #expect(store.saved.map(\.content) == [.text("two"), .text("one")])

        model.setRecording(false)
        #expect(model.entries.isEmpty)

        let relaunched = ClipboardHistoryViewModel(clipboard: SpyClipboard(), store: store)
        relaunched.setSavesHistory(true)
        relaunched.setRecording(true)
        #expect(relaunched.entries.map(\.content) == [.text("two"), .text("one")])
    }

    @Test func turningSavingOffErasesDiskAndTrims() {
        let store = MemoryStore()
        let clipboard = SpyClipboard()
        let model = ClipboardHistoryViewModel(clipboard: clipboard, store: store)
        model.setSavesHistory(true)
        model.setRecording(true)
        record((0..<40).map(String.init), clipboard: clipboard, model: model)
        #expect(model.entries.count == 40)

        model.setSavesHistory(false)
        #expect(store.eraseCount == 1)
        #expect(store.saved.isEmpty)
        #expect(model.entries.count == ClipboardHistoryViewModel.maxEntries)
    }

    @Test func leftoverFileIsErasedWhenSavingStartsOff() {
        let store = MemoryStore()
        store.saved = [ClipboardEntry(content: .text("old"), copiedAt: Date(), sourceBundleIdentifier: nil)]
        let model = ClipboardHistoryViewModel(clipboard: SpyClipboard(), store: store)
        model.setSavesHistory(false)
        #expect(store.saved.isEmpty)
        model.setSavesHistory(false)
        #expect(store.eraseCount == 1)
    }

    @Test func clearingErasesSavedHistory() {
        let store = MemoryStore()
        let model = ClipboardHistoryViewModel(clipboard: SpyClipboard(), store: store)
        model.setSavesHistory(true)
        model.setRecording(true)
        model.clear()
        #expect(store.eraseCount == 1)
    }

    @Test func searchMatchesTextLinksAndFileNames() {
        let clipboard = SpyClipboard()
        let model = ClipboardHistoryViewModel(clipboard: clipboard, store: MemoryStore())
        model.setRecording(true)
        let url = try? #require(URL(string: "https://deskcast.app/indir"))
        for content: ClipboardEntry.Content in [
            .text("Toplantı notları"),
            .url(url ?? URL(fileURLWithPath: "/")),
            .files([URL(fileURLWithPath: "/tmp/Rapor.pdf")]),
            .image(NSImage(size: CGSize(width: 2, height: 2)))
        ] {
            clipboard.copy(content)
            model.poll()
        }

        model.query = "toplanti"
        #expect(model.visibleEntries.map(\.content) == [.text("Toplantı notları")])
        model.query = "deskcast"
        #expect(model.visibleEntries.count == 1)
        model.query = "rapor"
        #expect(model.visibleEntries.count == 1)
        model.query = "  "
        #expect(model.visibleEntries.count == 4)
    }

    @Test func fileStoreRoundTripsWithoutImages() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = ClipboardHistoryFileStore(fileURL: fileURL)
        let date = Date(timeIntervalSince1970: 1_000)
        let url = try #require(URL(string: "https://example.com/a"))
        store.save([
            ClipboardEntry(content: .text("hi"), copiedAt: date, sourceBundleIdentifier: "com.apple.Notes"),
            ClipboardEntry(content: .image(NSImage(size: CGSize(width: 1, height: 1))), copiedAt: date, sourceBundleIdentifier: nil),
            ClipboardEntry(content: .url(url), copiedAt: date, sourceBundleIdentifier: nil),
            ClipboardEntry(content: .files([URL(fileURLWithPath: "/tmp/x.txt")]), copiedAt: date, sourceBundleIdentifier: nil)
        ])
        store.flush()

        let loaded = store.load()
        #expect(loaded.map(\.content) == [.text("hi"), .url(url), .files([URL(fileURLWithPath: "/tmp/x.txt")])])
        #expect(loaded.first?.sourceBundleIdentifier == "com.apple.Notes")
        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        store.erase()
        store.flush()
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }
}
