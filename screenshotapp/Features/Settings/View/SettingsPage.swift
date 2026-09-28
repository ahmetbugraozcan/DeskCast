import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case menuBar
    case screenshots
    case videoRecording
    case dropShelf
    case finderPath
    case dynamicIsland
    case shortcuts
    case about

    var id: Self { self }

    static let appSections: [Self] = [.menuBar, .shortcuts, .about]
    static let featureSections: [Self] = [.screenshots, .videoRecording, .dropShelf, .finderPath, .dynamicIsland]

    var title: String {
        switch self {
        case .menuBar: AppLocalization.string("Menu Bar")
        case .screenshots: AppLocalization.string("Screenshots")
        case .videoRecording: AppLocalization.string("Video Recording")
        case .dropShelf: AppLocalization.string("Drop Shelf")
        case .finderPath: AppLocalization.string("Finder Path")
        case .dynamicIsland: AppLocalization.string("Dynamic Island")
        case .shortcuts: AppLocalization.string("Shortcuts")
        case .about: AppLocalization.string("About DeskCast")
        }
    }

    var systemImage: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .screenshots: "camera.viewfinder"
        case .videoRecording: "record.circle"
        case .dropShelf: "tray.and.arrow.down"
        case .finderPath: "folder"
        case .dynamicIsland: ToolboxToolID.dynamicIsland.systemImage
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }

    /// Icon tile color, in the spirit of System Settings.
    var tint: Color {
        switch self {
        case .menuBar: .blue
        case .screenshots: .purple
        case .videoRecording: .red
        case .dropShelf: .orange
        case .finderPath: .cyan
        case .dynamicIsland: Color(white: 0.32)
        case .shortcuts: .gray
        case .about: .indigo
        }
    }

    var subtitle: String {
        AppLocalization.string("settings.subtitle.\(rawValue)")
    }
}

/// White symbol on a colored rounded square, used in the sidebar and page headers.
struct SettingsIconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(tint.gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}

private struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .formStyle(.grouped)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct SettingsPage<Content: View>: View {
    let section: SettingsSection
    @ViewBuilder var content: Content

    var body: some View {
        SettingsPane {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    SettingsIconTile(systemImage: section.systemImage, tint: section.tint, size: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.title2.weight(.semibold))
                        Text(section.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
