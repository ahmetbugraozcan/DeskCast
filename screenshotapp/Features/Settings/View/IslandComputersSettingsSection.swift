import SwiftUI

/// The computers the island's Computers panel can wake: a name, the MAC
/// address for Wake-on-LAN and, for the online status, an IP or `.local`
/// name. Saved as the fields change.
struct IslandComputersSettingsSection: View {
    @State private var computers: [WakeComputer] = []

    var body: some View {
        SettingsControlSection(title: AppLocalization.string("island.settings.computers")) {
            ForEach($computers) { $computer in
                ComputerRow(computer: $computer) {
                    computers.removeAll { $0.id == computer.id }
                }
                SettingsSectionDivider()
            }

            HStack {
                Button(AppLocalization.string("island.settings.computers.add"), systemImage: "plus") {
                    computers.append(WakeComputer())
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Text(AppLocalization.string("island.settings.computers.hint"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { computers = WakeComputer.load() }
        .onChange(of: computers) { _, newValue in
            WakeComputer.save(newValue)
        }
    }
}

private struct ComputerRow: View {
    @Binding var computer: WakeComputer
    let onRemove: () -> Void

    private var macIsInvalid: Bool {
        !computer.mac.trimmingCharacters(in: .whitespaces).isEmpty && computer.macBytes == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(AppLocalization.string("island.settings.computers.name"), text: $computer.name)
                    .frame(maxWidth: .infinity)
                TextField(AppLocalization.string("island.settings.computers.mac"), text: $computer.mac)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 170)
                TextField(AppLocalization.string("island.settings.computers.host"), text: $computer.host)
                    .frame(width: 150)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(AppLocalization.string("island.settings.computers.remove"))
            }
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()

            if macIsInvalid {
                Text(AppLocalization.string("island.computers.invalidMAC"))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
