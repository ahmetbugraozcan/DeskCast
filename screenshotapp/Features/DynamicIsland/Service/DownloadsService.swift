import AppKit

nonisolated struct DownloadedFile: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    let date: Date
    let size: Int64?

    var id: URL { url }
}

/// Newest items in ~/Downloads. macOS asks once before DeskCast may read it.
nonisolated struct DownloadsService: Sendable {
    var folderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    func recentFiles(limit: Int = 8) -> [DownloadedFile] {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey, .fileSizeKey, .isDirectoryKey]

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .compactMap { url -> DownloadedFile? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                // Skip in-progress browser downloads.
                guard !["crdownload", "download", "part"].contains(url.pathExtension) else { return nil }

                return DownloadedFile(
                    url: url,
                    name: url.lastPathComponent,
                    date: values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast,
                    size: values?.isDirectory == true ? nil : values?.fileSize.map(Int64.init)
                )
            }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }
}
