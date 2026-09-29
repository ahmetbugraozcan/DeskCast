import SwiftUI

/// Card surface shared by every Settings group: a soft fill with a hairline
/// border, readable in both light and dark appearance.
private struct SettingsCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(shape.fill(Color.primary.opacity(0.045)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

extension View {
    func settingsCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(SettingsCardModifier(cornerRadius: cornerRadius))
    }
}

/// Small caps title above a Settings group.
struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
    }
}

struct SettingsControlSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: title)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsControlRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .medium))

            Spacer(minLength: 18)

            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsPickerRow<Content: View>: View {
    let title: String
    @ViewBuilder var picker: Content

    var body: some View {
        SettingsControlRow(title: title) {
            picker
                .labelsHidden()
                .frame(width: 190)
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

struct SettingsSectionDivider: View {
    var body: some View {
        Divider()
            .opacity(0.6)
            .padding(.leading, 18)
    }
}

struct FeatureResetSection: View {
    let resetAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: AppLocalization.string("Reset Settings"))

            HStack(spacing: 12) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(0.12), in: Circle())

                Text(AppLocalization.string("Reset All Settings"))
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Button(AppLocalization.string("Reset"), role: .destructive) {
                    resetAction()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .settingsCard()
        }
    }
}
