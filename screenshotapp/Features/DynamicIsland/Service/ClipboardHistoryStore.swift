import Foundation

/// Saves the clipboard history between launches when the user opts in.
@MainActor
protocol ClipboardHistoryPersisting: AnyObject {
    func load() -> [ClipboardEntry]
    func save(_ entries: [ClipboardEntry])
    /// Deletes the saved history from disk.
    func erase()
}

/// Codable form of a history entry. Images are never written to disk.
nonisolated struct StoredClipboardEntry: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text, url, files
    }

    let kind: Kind
    let value: [String]
    let copiedAt: Date
    let sourceBundleIdentifier: String?
}

extension StoredClipboardEntry {
    init?(_ entry: ClipboardEntry) {
        switch entry.content {
        case .text(let text):
            kind = .text
            value = [text]
        case .url(let url):
            kind = .url
            value = [url.absoluteString]
        case .files(let urls):
            kind = .files
            value = urls.map(\.path)
        case .image:
            return nil
        }
        copiedAt = entry.copiedAt
        sourceBundleIdentifier = entry.sourceBundleIdentifier
    }

    var entry: ClipboardEntry? {
        let content: ClipboardEntry.Content
        switch kind {
        case .text:
            guard let text = value.first else { return nil }
            content = .text(text)
        case .url:
            guard let url = value.first.flatMap(URL.init(string:)) else { return nil }
            content = .url(url)
        case .files:
            guard !value.isEmpty else { return nil }
            content = .files(value.map { URL(fileURLWithPath: $0) })
        }
        return ClipboardEntry(content: content, copiedAt: copiedAt, sourceBundleIdentifier: sourceBundleIdentifier)
    }
}

/// JSON file in Application Support, readable only by the user. Writes happen
/// off the main thread, in order.
@MainActor
final class ClipboardHistoryFileStore: ClipboardHistoryPersisting {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.deskcast.clipboard-history", qos: .utility)

    init(fileURL: URL = ClipboardHistoryFileStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("DeskCast", isDirectory: true)
            .appendingPathComponent("ClipboardHistory.json")
    }

    func load() -> [ClipboardEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([StoredClipboardEntry].self, from: data) else {
            return []
        }
        return stored.compactMap(\.entry)
    }

    func save(_ entries: [ClipboardEntry]) {
        let stored = entries.compactMap(StoredClipboardEntry.init)
        let fileURL = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(stored) else { return }
            let directory = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    }

    func erase() {
        let fileURL = fileURL
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Waits for pending writes; used by tests.
    func flush() {
        queue.sync {}
    }
}
