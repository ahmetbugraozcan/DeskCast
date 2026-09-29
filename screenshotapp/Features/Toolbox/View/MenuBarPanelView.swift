import AppKit
import KeyboardShortcuts
import SwiftUI

/// Which parts of the menu bar panel are visible; mirrors the menu's
/// `enabled && showInMenu` rules so disabled tools never show up.
struct MenuBarPanelVisibility {
    var captureSelectedArea: Bool
    var captureVideo: Bool
    var captureOCR: Bool
    var imageSearch: Bool
    var copyFinderPath: Bool
    var dropShelf: Bool
    var dynamicIsland: Bool

    var toolCount: Int {
        [captureSelectedArea, captureVideo, captureOCR, imageSearch, copyFinderPath, dropShelf, dynamicIsland]
            .filter { $0 }
            .count
    }

    var hasTools: Bool {
        captureSelectedArea || captureVideo || captureOCR || imageSearch || copyFinderPath || dropShelf || dynamicIsland
    }
}

/// App-level actions the panel can't perform from its view models alone.
struct MenuBarPanelActions {
    let openImageSearch: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void
}

/// The menu bar popover: tool tiles, the playing track, recent captures and
/// the Drop Shelf at a glance. Shown with `.menuBarExtraStyle(.window)`.
struct MenuBarPanelView: View {
    @ObservedObject var screenshots: ScreenshotShelfViewModel
    @ObservedObject var recorder: ScreenRecordingViewModel
    @ObservedObject var dropShelf: DropShelfViewModel
    @ObservedObject var island: DynamicIslandViewModel
    let visibility: MenuBarPanelVisibility
    let actions: MenuBarPanelActions

    private static let width: CGFloat = 340
    private static let recentCaptureLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if recorder.isRecording {
                recordingBanner
            }

            if visibility.hasTools {
                toolGrid
            }

            if visibility.dynamicIsland, let nowPlaying = island.nowPlaying {
                nowPlayingCard(nowPlaying)
            }

            if !screenshots.screenshots.isEmpty {
                recentCaptures
            }

            if visibility.dropShelf, !dropShelf.items.isEmpty {
                dropShelfRow
            }
        }
        .padding(14)
        .frame(width: Self.width)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                )

            Text(AppConstants.displayName)
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            MenuPanelIconButton(systemImage: "gearshape", help: AppLocalization.string("Settings")) {
                dismissPanel()
                actions.openSettings()
            }

            MenuPanelIconButton(systemImage: "power", help: AppLocalization.formatted("Quit %@", AppConstants.displayName)) {
                actions.quit()
            }
        }
    }

    // MARK: - Tools

    private var toolGrid: some View {
        // Four columns once a third row would hold a lone tile.
        let columnCount = visibility.toolCount > 6 ? 4 : 3

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount), spacing: 8) {
            if visibility.captureSelectedArea {
                MenuPanelTile(
                    title: AppLocalization.string("menu.tile.screenshot"),
                    systemImage: "camera.viewfinder",
                    tint: .purple,
                    shortcut: .captureSelectedArea
                ) {
                    runAfterDismiss { screenshots.captureSelectedArea() }
                }
                .disabled(screenshots.isCapturing)
            }

            if visibility.captureVideo {
                MenuPanelTile(
                    title: AppLocalization.string("menu.tile.record"),
                    systemImage: "record.circle",
                    tint: .red,
                    shortcut: .captureVideo
                ) {
                    runAfterDismiss { recorder.captureSelectedAreaVideo() }
                }
                .disabled(recorder.isRecording)
            }

            if visibility.captureOCR {
                MenuPanelTile(title: AppLocalization.string("menu.tile.copyText"), systemImage: "text.viewfinder", tint: .teal) {
                    runAfterDismiss { screenshots.captureOCRTextFromSelectedArea() }
                }
                .disabled(screenshots.isCapturing)
            }

            if visibility.imageSearch {
                MenuPanelTile(title: AppLocalization.string("menu.tile.imageSearch"), systemImage: "magnifyingglass", tint: .blue) {
                    dismissPanel()
                    actions.openImageSearch()
                }
            }

            if visibility.copyFinderPath {
                MenuPanelTile(title: AppLocalization.string("menu.tile.finderPath"), systemImage: "folder", tint: .cyan) {
                    runAfterDismiss { screenshots.copyFrontFinderPath() }
                }
            }

            if visibility.dropShelf {
                MenuPanelTile(
                    title: AppLocalization.string("menu.tile.dropShelf"),
                    systemImage: "tray.and.arrow.down",
                    tint: .orange,
                    shortcut: .openDropShelf,
                    isOn: dropShelf.isShelfVisible
                ) {
                    dropShelf.toggleShelf()
                }
            }

            if visibility.dynamicIsland {
                MenuPanelTile(title: AppLocalization.string("menu.tile.island"), systemImage: "capsule.fill", tint: Color(white: 0.25)) {
                    runAfterDismiss { island.open(island.lastSelectedPanel) }
                }
            }
        }
    }

    private var recordingBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            Text(AppLocalization.string("menu.recording"))
                .font(.system(size: 12, weight: .semibold))

            Text(Self.formatDuration(TimeInterval(recorder.elapsedSeconds)))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                recorder.stopRecording()
            } label: {
                Label(AppLocalization.string("menu.recording.stop"), systemImage: "stop.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(10)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Now Playing

    private func nowPlayingCard(_ nowPlaying: NowPlayingInfo) -> some View {
        HStack(spacing: 10) {
            Button {
                island.openPlayer()
            } label: {
                Group {
                    if let artwork = nowPlaying.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary)
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(AppLocalization.formatted("Open %@", nowPlaying.source.displayName))

            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text(nowPlaying.artist.isEmpty ? nowPlaying.source.displayName : nowPlaying.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                MenuPanelIconButton(systemImage: "backward.fill", help: AppLocalization.string("Previous Track")) {
                    island.previousTrack()
                }
                .disabled(!nowPlaying.capabilities.canGoBack)

                MenuPanelIconButton(
                    systemImage: nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                    help: AppLocalization.string("Play / Pause")
                ) {
                    island.togglePlayPause()
                }

                MenuPanelIconButton(systemImage: "forward.fill", help: AppLocalization.string("Next Track")) {
                    island.nextTrack()
                }
                .disabled(!nowPlaying.capabilities.canSkip)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Captures

    private var recentCaptures: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(AppLocalization.string("menu.recentCaptures"))

                Spacer()

                Button(AppLocalization.string("Copy All")) {
                    screenshots.copyAll()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))

                Button(AppLocalization.string("Clear All")) {
                    screenshots.clearAll()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }

            HStack(spacing: 6) {
                ForEach(screenshots.screenshots.suffix(Self.recentCaptureLimit).reversed()) { item in
                    captureThumbnail(item)
                }
            }
        }
    }

    private func captureThumbnail(_ item: ScreenshotItem) -> some View {
        Button {
            screenshots.copy(item)
        } label: {
            Image(nsImage: item.image)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if item.kind == .video {
                        Image(systemName: "video.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(3)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(AppLocalization.string("menu.recentCaptures.copyHelp"))
        .onDrag {
            if let url = item.fileURL, let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
            return NSItemProvider(object: item.image)
        }
        .contextMenu {
            Button(AppLocalization.string("Copy")) { screenshots.copy(item) }

            if item.fileURL != nil {
                Button(AppLocalization.string("Show in Finder")) { screenshots.showInFinder(item) }
            }

            Divider()

            Button(AppLocalization.string("Remove"), role: .destructive) { screenshots.remove(item) }
        }
    }

    // MARK: - Drop Shelf

    private var dropShelfRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full.fill")
                .foregroundStyle(.orange)

            Text(
                dropShelf.items.count == 1
                    ? AppLocalization.formatted("menu.dropShelf.count.one", dropShelf.items.count)
                    : AppLocalization.formatted("menu.dropShelf.count.other", dropShelf.items.count)
            )
            .font(.system(size: 12, weight: .medium))

            Spacer()

            MenuPanelIconButton(systemImage: "paperplane", help: AppLocalization.string("Send Shelf Items")) {
                dropShelf.sendAll()
            }

            MenuPanelIconButton(systemImage: "trash", help: AppLocalization.string("Clear Drop Shelf")) {
                dropShelf.clearAll()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    /// Closes the popover (MenuBarExtra has no dismiss action for windows).
    private func dismissPanel() {
        NSApp.windows
            .filter { $0.isVisible && $0.className.contains("MenuBarExtra") }
            .forEach { $0.close() }
        NSApp.keyWindow?.close()
    }

    /// Interactive captures must not include the popover, so close it and let
    /// it fade before starting.
    private func runAfterDismiss(_ action: @escaping @MainActor () -> Void) {
        dismissPanel()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            action()
        }
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct MenuPanelTile: View {
    let title: String
    let systemImage: String
    let tint: Color
    /// Global shortcut shown under the title when one is set.
    var shortcut: KeyboardShortcuts.Name?
    var isOn = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint.gradient))

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            // A corner badge keeps the icons of neighboring tiles aligned.
            .overlay(alignment: .topTrailing) {
                if let shortcut, let keys = KeyboardShortcuts.getShortcut(for: shortcut) {
                    Text(keys.description)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .padding(.trailing, 7)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? tint.opacity(0.22) : Color.primary.opacity(isHovered ? 0.1 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? tint.opacity(0.55) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct MenuPanelIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.12 : 0)))
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovered = $0 }
    }
}
