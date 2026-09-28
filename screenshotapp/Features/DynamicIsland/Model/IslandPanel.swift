import AppKit
import KeyboardShortcuts
import SwiftUI

/// The pages the expanded island can show. Order is the launcher grid order.
enum IslandPanel: String, CaseIterable, Identifiable {
    case controls
    case volume
    case nowPlaying
    case captures
    case files
    case system
    case tools
    case calendar
    case notifications
    case timer
    case camera
    case downloads
    case scratchpad
    case aiAgents

    var id: String { rawValue }

    /// Localization key; resolved in the view layer.
    var titleKey: String {
        switch self {
        case .controls: "island.panel.controls"
        case .volume: "island.panel.volume"
        case .nowPlaying: "island.panel.nowPlaying"
        case .captures: "island.panel.captures"
        case .files: "island.panel.files"
        case .system: "island.panel.system"
        case .tools: "island.panel.tools"
        case .calendar: "island.panel.calendar"
        case .notifications: "island.panel.notifications"
        case .timer: "island.panel.timer"
        case .camera: "island.panel.camera"
        case .downloads: "island.panel.downloads"
        case .scratchpad: "island.panel.scratchpad"
        case .aiAgents: "island.panel.aiAgents"
        }
    }

    var systemImage: String {
        switch self {
        case .controls: "slider.horizontal.3"
        case .volume: "speaker.wave.2"
        case .nowPlaying: "music.note"
        case .captures: "camera.viewfinder"
        case .files: "tray"
        case .system: "gauge.with.dots.needle.50percent"
        case .tools: "square.grid.2x2"
        case .calendar: "calendar"
        case .notifications: "bell"
        case .timer: "timer"
        case .camera: "web.camera"
        case .downloads: "arrow.down.circle"
        case .scratchpad: "note.text"
        case .aiAgents: "sparkles"
        }
    }

    /// Icon tint in the launcher grid (nil = white).
    var tint: Color? {
        switch self {
        case .nowPlaying: Color(red: 1, green: 0.27, blue: 0.4)
        case .calendar: Color(red: 1, green: 0.3, blue: 0.3)
        case .timer: Color(red: 1, green: 0.6, blue: 0.2)
        default: nil
        }
    }

    /// Letter of the ⌥⌘ shortcut shown on the launcher tile.
    var shortcutKey: KeyboardShortcuts.Key {
        switch self {
        case .controls: .c
        case .volume: .v
        case .nowPlaying: .m
        case .captures: .s
        case .files: .f
        case .system: .i
        case .tools: .t
        case .calendar: .a
        case .notifications: .n
        case .timer: .r
        case .camera: .w
        case .downloads: .d
        case .scratchpad: .p
        case .aiAgents: .g
        }
    }

    var shortcutName: KeyboardShortcuts.Name {
        Self.shortcutNames[self] ?? KeyboardShortcuts.Name("island.\(rawValue)")
    }

    /// Created once: `Name(_:default:)` registers the default binding.
    private static let shortcutNames: [IslandPanel: KeyboardShortcuts.Name] = Dictionary(
        uniqueKeysWithValues: allCases.map { panel in
            (
                panel,
                KeyboardShortcuts.Name(
                    "island.\(panel.rawValue)",
                    default: .init(panel.shortcutKey, modifiers: [.option, .command])
                )
            )
        }
    )

    /// Shortcut label for the tile, e.g. "⌥⌘M"; follows user re-bindings.
    var shortcutLabel: String? {
        KeyboardShortcuts.getShortcut(for: shortcutName)?.description
    }

    /// Scratchpad needs keyboard focus, so the panel may become key for it.
    var needsKeyboard: Bool {
        self == .scratchpad
    }
}

/// What the expanded island shows: the panel grid or one panel.
enum IslandExpandedContent: Equatable {
    case launcher
    case panel(IslandPanel)
}
