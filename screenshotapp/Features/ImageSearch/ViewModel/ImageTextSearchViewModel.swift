import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ImageTextSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var folderURL: URL?
    @Published private(set) var items: [ImageSearchItem] = []
    @Published private(set) var isIndexing = false
    @Published private(set) var indexedCount = 0

    private var indexingTask: Task<Void, Never>?

    deinit {
        indexingTask?.cancel()
    }

    var results: [ImageSearchMatch] {
        let normalizedQuery = normalized(query)

        guard !normalizedQuery.isEmpty else {
            return items.map { item in
                ImageSearchMatch(
                    item: item,
                    matchedFilename: false,
                    matchedText: false,
                    textSnippet: nil
                )
            }
        }

        return items.compactMap { item in
            let matchedFilename = normalized(item.filename).contains(normalizedQuery)
            let matchedText = normalized(item.recognizedText ?? "").contains(normalizedQuery)

            guard matchedFilename || matchedText else {
                return nil
            }

            return ImageSearchMatch(
                item: item,
                matchedFilename: matchedFilename,
                matchedText: matchedText,
                textSnippet: matchedText ? textSnippet(in: item.recognizedText ?? "", query: query) : nil
            )
        }
    }

    var statusText: String {
        guard folderURL != nil else {
            return AppLocalization.string("No folder selected")
        }

        if isIndexing {
            return AppLocalization.formatted("%ld / %ld indexed", indexedCount, items.count)
        }

        return AppLocalization.formatted("%ld images", items.count)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = AppLocalization.string("Choose")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        loadFolder(url)
    }

    func reindex() {
        guard let folderURL else {
            chooseFolder()
            return
        }

        loadFolder(folderURL)
    }

    func open(_ item: ImageSearchItem) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: ImageSearchItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func loadFolder(_ url: URL) {
        indexingTask?.cancel()
        folderURL = url
        items = []
        indexedCount = 0
        isIndexing = true

        indexingTask = Task { [weak self] in
            let imageURLs = await Task.detached(priority: .userInitiated) {
                Self.imageURLs(in: url)
            }.value

            guard let self, !Task.isCancelled else {
                return
            }

            items = imageURLs.map { ImageSearchItem(url: $0) }
            isIndexing = !imageURLs.isEmpty

            guard !imageURLs.isEmpty else {
                isIndexing = false
                return
            }

            for imageURL in imageURLs {
                if Task.isCancelled {
                    return
                }

                updateItem(imageURL) { item in
                    item.indexState = .scanning
                }

                let result = await Self.recognizedText(at: imageURL)

                if Task.isCancelled {
                    return
                }

                markIndexed(imageURL, text: result.text, state: result.state)
            }

            isIndexing = false
        }
    }

    private nonisolated static func recognizedText(
        at imageURL: URL
    ) async -> (text: String?, state: ImageSearchIndexState) {
        guard let image = NSImage(contentsOf: imageURL) else {
            return (nil, .failed)
        }

        do {
            let text = try await OCRTextRecognitionService.recognizeText(in: image)
            return (text, .indexed)
        } catch {
            return (nil, .indexed)
        }
    }

    private func markIndexed(_ url: URL, text: String?, state: ImageSearchIndexState) {
        updateItem(url) { item in
            item.recognizedText = text
            item.indexState = state
        }
        indexedCount += 1
    }

    private func updateItem(_ url: URL, update: (inout ImageSearchItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.url == url }) else {
            return
        }

        update(&items[index])
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func textSnippet(in text: String, query: String) -> String? {
        let normalizedQuery = normalized(query)

        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                normalized(line).contains(normalizedQuery)
            }
    }

    private nonisolated static func imageURLs(in folderURL: URL) -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentTypeKey
        ]
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                guard
                    let values = try? url.resourceValues(forKeys: resourceKeys),
                    values.isRegularFile == true
                else {
                    return false
                }

                if let contentType = values.contentType {
                    return contentType.conforms(to: .image)
                }

                guard let type = UTType(filenameExtension: url.pathExtension) else {
                    return false
                }

                return type.conforms(to: .image)
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }
}
