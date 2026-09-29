import AppKit
import Testing
@testable import screenshotapp

@MainActor
private final class FakeClipboard: ClipboardAccessing {
    var changeCount = 0
    var current: ClipboardEntry?
    private(set) var written: [ClipboardEntry] = []

    func currentEntry() -> ClipboardEntry? { current }

    func write(_ entry: ClipboardEntry) -> Int {
        written.append(entry)
        current = entry
        changeCount += 1
        return changeCount
    }

    func copy(_ text: String) {
        current = ClipboardEntry(content: .text(text), copiedAt: Date(), sourceBundleIdentifier: nil)
        changeCount += 1
    }
}

@MainActor
struct ClipboardHistoryTests {
    @Test func recordsNewCopiesNewestFirst() {
        let clipboard = FakeClipboard()
        let model = ClipboardHistoryViewModel(clipboard: clipboard)
        model.setRecording(true)

        clipboard.copy("one")
        model.poll()
        clipboard.copy("two")
        model.poll()

        #expect(model.entries.map(\.content) == [.text("two"), .text("one")])
    }

    @Test func repeatedCopyMovesToTopWithoutDuplicating() {
        let clipboard = FakeClipboard()
        let model = ClipboardHistoryViewModel(clipboard: clipboard)
        model.setRecording(true)

        for text in ["a", "b", "a"] {
            clipboard.copy(text)
            model.poll()
        }

        #expect(model.entries.map(\.content) == [.text("a"), .text("b")])
    }

    @Test func copyingAnEntryBackDoesNotRecordItTwice() throws {
        let clipboard = FakeClipboard()
        let model = ClipboardHistoryViewModel(clipboard: clipboard)
        model.setRecording(true)

        for text in ["a", "b"] {
            clipboard.copy(text)
            model.poll()
        }

        let older = try #require(model.entries.last)
        model.copy(older)
        model.poll()

        #expect(model.entries.map(\.content) == [.text("a"), .text("b")])
        #expect(clipboard.written.map(\.content) == [.text("a")])
    }

    @Test func stoppingForgetsHistoryAndIgnoresCopies() {
        let clipboard = FakeClipboard()
        let model = ClipboardHistoryViewModel(clipboard: clipboard)
        model.setRecording(true)
        clipboard.copy("secret")
        model.poll()

        model.setRecording(false)
        #expect(model.entries.isEmpty)

        clipboard.copy("later")
        model.poll()
        #expect(model.entries.isEmpty)
    }

    @Test func keepsAtMostTheLimit() {
        let clipboard = FakeClipboard()
        let model = ClipboardHistoryViewModel(clipboard: clipboard)
        model.setRecording(true)

        for index in 0..<(ClipboardHistoryViewModel.maxEntries + 5) {
            clipboard.copy("item \(index)")
            model.poll()
        }

        #expect(model.entries.count == ClipboardHistoryViewModel.maxEntries)
        #expect(model.entries.first?.content == .text("item \(ClipboardHistoryViewModel.maxEntries + 4)"))
    }
}
