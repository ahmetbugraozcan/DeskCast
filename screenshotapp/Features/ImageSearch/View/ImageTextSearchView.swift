import AppKit
import SwiftUI

struct ImageTextSearchView: View {
    @StateObject private var store = ImageTextSearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            searchToolbar

            Divider()
                .opacity(0.5)

            content
        }
        .frame(minWidth: 680, minHeight: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
    }

    private var searchToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SearchField(text: $store.query)

                Button {
                    store.chooseFolder()
                } label: {
                    Label(AppLocalization.string("Choose Folder"), systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    store.reindex()
                } label: {
                    Label(AppLocalization.string("Reindex"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.folderURL == nil)
            }
            .controlSize(.large)

            statusRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if store.isIndexing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Text(store.statusText)
                .foregroundStyle(.secondary)

            if let folderURL = store.folderURL {
                Text("·")
                    .foregroundStyle(.quaternary)

                Text(folderURL.path)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var content: some View {
        if store.folderURL == nil {
            ImageSearchEmptyState(
                title: AppLocalization.string("Choose a Folder"),
                message: AppLocalization.string("Pick a folder of images to index and search by text."),
                systemImage: "folder.badge.plus",
                actionTitle: AppLocalization.string("Choose Folder"),
                action: { store.chooseFolder() }
            )
        } else if store.items.isEmpty {
            ImageSearchEmptyState(
                title: AppLocalization.string("No Images"),
                message: nil,
                systemImage: "photo.stack",
                actionTitle: nil,
                action: nil
            )
        } else if store.results.isEmpty {
            ImageSearchEmptyState(
                title: AppLocalization.string("No Results"),
                message: nil,
                systemImage: "magnifyingglass",
                actionTitle: nil,
                action: nil
            )
        } else {
            resultsGrid
        }
    }

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 196, maximum: 240), spacing: 18)],
                spacing: 18
            ) {
                ForEach(store.results, id: \.item.id) { match in
                    ImageSearchResultCard(
                        match: match,
                        openAction: { store.open(match.item) },
                        revealAction: { store.revealInFinder(match.item) }
                    )
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(AppLocalization.string("Search filename or image text"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

private struct ImageSearchResultCard: View {
    let match: ImageSearchMatch
    let openAction: () -> Void
    let revealAction: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: openAction) {
            VStack(alignment: .leading, spacing: 10) {
                ImageSearchThumbnail(url: match.item.url)
                    .frame(height: 126)

                Text(match.item.filename)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)

                matchRow

                snippetArea
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 224, alignment: .top)
            .padding(11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(isHovering ? 0.18 : 0.08), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(isHovering ? 0.22 : 0.1),
                radius: isHovering ? 16 : 8,
                y: isHovering ? 8 : 4
            )
            .scaleEffect(isHovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.32, dampingFraction: 1), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button {
                openAction()
            } label: {
                Label(AppLocalization.string("Open"), systemImage: "arrow.up.right.square")
            }

            Button {
                revealAction()
            } label: {
                Label(AppLocalization.string("Reveal in Finder"), systemImage: "finder")
            }

            Button {
                copyPath()
            } label: {
                Label(AppLocalization.string("Copy Path"), systemImage: "doc.on.doc")
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
            HStack(spacing: 6) {
                ForEach(match.matchLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
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
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.6))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .clipped()
        .task(id: url) {
            image = NSImage(contentsOf: url)
        }
    }
}

private struct ImageSearchEmptyState: View {
    let title: String
    let message: String?
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)

                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
