import AppKit
import SwiftUI

struct ImageTextSearchView: View {
    @StateObject private var store = ImageTextSearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            searchToolbar

            Divider()

            content
        }
        .frame(minWidth: 640, minHeight: 430)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var searchToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SearchField(text: $store.query)

                Button {
                    store.chooseFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                }

                Button {
                    store.reindex()
                } label: {
                    Label("Reindex", systemImage: "arrow.clockwise")
                }
                .disabled(store.folderURL == nil)
            }

            HStack(spacing: 8) {
                if store.isIndexing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                }

                Text(store.statusText)
                    .foregroundStyle(.secondary)

                if let folderURL = store.folderURL {
                    Text(folderURL.path)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if store.folderURL == nil {
            ImageSearchEmptyState(
                title: AppLocalization.string("Choose a Folder"),
                systemImage: "folder.badge.plus"
            )
        } else if store.items.isEmpty {
            ImageSearchEmptyState(
                title: AppLocalization.string("No Images"),
                systemImage: "photo.stack"
            )
        } else if store.results.isEmpty {
            ImageSearchEmptyState(
                title: AppLocalization.string("No Results"),
                systemImage: "magnifyingglass"
            )
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)
                    ],
                    spacing: 16
                ) {
                    ForEach(store.results, id: \.item.id) { match in
                        ImageSearchResultCard(
                            match: match,
                            openAction: { store.open(match.item) },
                            revealAction: { store.revealInFinder(match.item) }
                        )
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search filename or image text", text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ImageSearchResultCard: View {
    let match: ImageSearchMatch
    let openAction: () -> Void
    let revealAction: () -> Void

    var body: some View {
        Button(action: openAction) {
            VStack(alignment: .leading, spacing: 8) {
                ImageSearchThumbnail(url: match.item.url)
                    .frame(height: 116)

                Text(match.item.filename)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                matchRow

                snippetArea
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 206, alignment: .top)
            .padding(9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                openAction()
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            Button {
                revealAction()
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }

            Button {
                copyPath()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
    }

    @ViewBuilder
    private var snippetArea: some View {
        if let textSnippet = match.textSnippet {
            Text(textSnippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(height: 32, alignment: .top)
        } else {
            Color.clear
                .frame(height: 32)
        }
    }

    @ViewBuilder
    private var matchRow: some View {
        if match.matchLabels.isEmpty {
            ImageSearchStatusLabel(state: match.item.indexState)
        } else {
            HStack(spacing: 5) {
                ForEach(match.matchLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }

    private func copyPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(match.item.url.path, forType: .string)
    }
}

private struct ImageSearchStatusLabel: View {
    let state: ImageSearchIndexState

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var title: String {
        switch state {
        case .pending:
            AppLocalization.string("Queued")
        case .scanning:
            AppLocalization.string("Reading text")
        case .indexed:
            AppLocalization.string("Indexed")
        case .failed:
            AppLocalization.string("Unreadable")
        }
    }

    private var systemImage: String {
        switch state {
        case .pending:
            "clock"
        case .scanning:
            "text.viewfinder"
        case .indexed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }
}

private struct ImageSearchThumbnail: View {
    let url: URL

    @State private var image: NSImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .clipped()
        .task(id: url) {
            image = NSImage(contentsOf: url)
        }
    }
}

private struct ImageSearchEmptyState: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
