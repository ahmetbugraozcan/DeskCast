import SwiftUI

// MARK: - Computers

/// Computers to wake with Wake-on-LAN, each with its online status (when
/// it has an address) and a Wake button. They're added in Settings.
struct ComputersPanelView: View {
    @ObservedObject var model: WakeComputersViewModel
    let openSettings: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            if model.computers.isEmpty {
                IslandEmptyState(
                    systemImage: "desktopcomputer",
                    title: AppLocalization.string("island.computers.empty"),
                    message: AppLocalization.string("island.computers.emptyMessage"),
                    actionTitle: AppLocalization.string("island.computers.addInSettings"),
                    action: openSettings
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.computers) { computer in
                            WakeComputerCard(computer: computer, status: model.status(of: computer)) {
                                model.wake(computer)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .islandScrollFade()

                if model.failedWake != nil {
                    IslandChipButton(
                        title: AppLocalization.string("island.computers.sendFailed"),
                        systemImage: "network.slash"
                    ) { model.openLocalNetworkSettings() }
                }
            }
        }
        .activatesIslandPanel(model)
    }
}

private struct WakeComputerCard: View {
    let computer: WakeComputer
    let status: WakeComputerStatus
    let onWake: () -> Void

    private static let onlineColor = Color(red: 0.2, green: 0.84, blue: 0.42)
    private static let wakingColor = Color(red: 1, green: 0.74, blue: 0.2)

    private var hasValidMAC: Bool { computer.macBytes != nil }

    private var dotColor: Color {
        switch status {
        case .online: Self.onlineColor
        case .waking: Self.wakingColor
        case .offline, .away, .unknown: IslandPalette.track
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(status.isOnline ? .white : IslandPalette.secondaryText)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    .shadow(color: dotColor.opacity(status.isOnline ? 0.6 : 0), radius: 4)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(computer.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusText
            }

            Spacer(minLength: 0)

            wakeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IslandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(IslandPalette.cardStroke, lineWidth: 1))
        .animation(.easeOut(duration: 0.25), value: status)
    }

    @ViewBuilder
    private var statusText: some View {
        Group {
            if !hasValidMAC {
                Text(AppLocalization.string("island.computers.invalidMAC"))
                    .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.59))
            } else {
                switch status {
                case .online:
                    Text(AppLocalization.string("island.computers.online")).foregroundStyle(Self.onlineColor)
                case .offline:
                    Text(AppLocalization.string("island.computers.offline")).foregroundStyle(IslandPalette.tertiaryText)
                case .away:
                    Text(AppLocalization.string("island.computers.away")).foregroundStyle(IslandPalette.tertiaryText)
                case .waking(let since):
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(AppLocalization.formatted(
                            "island.computers.waking",
                            IslandFormat.clock(context.date.timeIntervalSince(since))
                        ))
                        .foregroundStyle(Self.wakingColor)
                    }
                case .unknown:
                    Text(AppLocalization.string(
                        computer.trimmedHost.isEmpty ? "island.computers.noAddress" : "island.computers.checking"
                    ))
                    .foregroundStyle(IslandPalette.tertiaryText)
                }
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .lineLimit(1)
    }

    private var wakeButton: some View {
        Button(action: onWake) {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(canWake ? Color.black : Color.white.opacity(0.35))
                .frame(width: 30, height: 30)
                .background(Circle().fill(canWake ? Color.white : Color.white.opacity(0.08)))
        }
        .buttonStyle(IslandScaleButtonStyle())
        .disabled(!canWake)
        .help(AppLocalization.string(status == .away ? "island.computers.awayHelp" : "island.computers.wake"))
        .accessibilityLabel(Text(AppLocalization.formatted("island.computers.wakeNamed", computer.displayName)))
    }

    private var canWake: Bool {
        guard hasValidMAC else { return false }
        switch status {
        case .online, .away: return false
        default: return true
        }
    }
}
