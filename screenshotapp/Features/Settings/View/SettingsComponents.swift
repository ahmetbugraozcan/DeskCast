import SwiftUI

struct SettingsControlSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
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
        .padding(.horizontal, 20)
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
                .labelsHidden()
        }
    }
}

struct SettingsSectionDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 20)
    }
}

struct FeatureResetSection: View {
    let resetAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Reset Settings")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            HStack(spacing: 14) {
                Spacer()

                Button(role: .destructive) {
                    resetAction()
                } label: {
                    Label("Reset All Settings", systemImage: "arrow.counterclockwise")
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
