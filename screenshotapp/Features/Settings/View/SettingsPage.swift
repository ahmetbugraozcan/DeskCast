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
        case .dynamicIsland: .pink
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
                // No focus ring on whichever control happens to be first.
                .focusEffectDisabled()
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
            VStack(alignment: .leading, spacing: 22) {
                SettingsPageHeader(section: section)

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Tinted banner at the top of every page: the section's icon, title and
/// subtitle over a soft gradient, with a large faded symbol as decoration.
private struct SettingsPageHeader: View {
    let section: SettingsSection

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        HStack(spacing: 16) {
            SettingsIconTile(systemImage: section.systemImage, tint: section.tint, size: 52)
                .shadow(color: section.tint.opacity(0.45), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.system(size: 22, weight: .bold))
                Text(section.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .trailing) {
                LinearGradient(
                    colors: [section.tint.opacity(0.32), section.tint.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: section.systemImage)
                    .font(.system(size: 96, weight: .semibold))
                    .foregroundStyle(section.tint.opacity(0.14))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 18, y: 10)
                    .accessibilityHidden(true)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(section.tint.opacity(0.25), lineWidth: 1))
    }
}

extension ToolboxToolID {
    /// Icon tile color for the tool's card in Settings.
    var settingsTint: Color {
        switch self {
        case .captureSelectedArea: .purple
        case .captureVideo: .red
        case .captureOCR: .teal
        case .copyFinderPath: .cyan
        case .imageSearch: .blue
        case .dropShelf: .orange
        case .dynamicIsland: .pink
        }
    }
}
