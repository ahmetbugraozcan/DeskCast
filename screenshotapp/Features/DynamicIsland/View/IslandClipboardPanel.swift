import AppKit
import SwiftUI

// MARK: - Clipboard

/// Recent copies. Clicking a row pastes it into the app you were using (the
/// island never takes focus); the copy button only puts it on the clipboard.
struct ClipboardPanelView: View {
    @ObservedObject var model: ClipboardHistoryViewModel

    var body: some View {
        if model.entries.isEmpty {
            IslandEmptyState(
                systemImage: "doc.on.clipboard",
                title: AppLocalization.string("island.clipboard.empty"),
                message: AppLocalization.string("island.clipboard.emptyMessage")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.entries) { entry in
                        ClipboardRow(entry: entry, model: model)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 10)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.entries.map(\.id))
            }
            .scrollIndicators(.never)
            .islandScrollFade()
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    @ObservedObject var model: ClipboardHistoryViewModel

    @State private var isHovered = false

    var body: some View {
        Button {
            model.paste(entry)
        } label: {
            HStack(spacing: 10) {
                preview
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    HStack(spacing: 4) {
                        if let icon = sourceIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 11, height: 11)
                        }

                        Text(entry.copiedAt, style: .relative)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(IslandPalette.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isHovered {
                    HStack(spacing: 2) {
                        IslandIconButton(
                            systemImage: "doc.on.doc",
                            help: AppLocalization.string("Copy"),
                            action: { model.copy(entry) }
                        )
                        IslandIconButton(
                            systemImage: "xmark",
                            help: AppLocalization.string("Remove"),
                            action: { model.remove(entry) }
                        )
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovered ? Color(white: 0.16) : IslandPalette.card)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(IslandScaleButtonStyle())
        .help(AppLocalization.string("island.clipboard.pasteHelp"))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private var preview: some View {
        switch entry.content {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .files(let urls):
            if let first = urls.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                    .resizable()
                    .scaledToFit()
            }
        case .url:
            symbol("link", tint: .blue)
        case .text:
            symbol("text.alignleft", tint: .white)
        }
    }

    private func symbol(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(white: 0.2)))
    }

    private var title: String {
        switch entry.content {
        case .text(let text):
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
        case .url(let url):
            url.absoluteString
        case .files(let urls):
            urls.count == 1
                ? urls[0].lastPathComponent
                : AppLocalization.formatted("island.clipboard.files", urls.count)
        case .image(let image):
            AppLocalization.formatted("island.clipboard.image", Int(image.size.width), Int(image.size.height))
        }
    }

    private var sourceIcon: NSImage? {
        guard let bundle = entry.sourceBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
