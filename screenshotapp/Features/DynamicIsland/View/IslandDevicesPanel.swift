import SwiftUI

// MARK: - Devices

/// Battery levels of connected Bluetooth accessories, as cards with ring
/// gauges: AirPods get one ring each for left, right and the case.
struct DevicesPanelView: View {
    @ObservedObject var model: DevicesViewModel
    @ObservedObject var ble: BLEBatteryService

    init(model: DevicesViewModel) {
        self.model = model
        ble = model.ble
    }

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            if model.devices.isEmpty {
                IslandEmptyState(
                    systemImage: "dot.radiowaves.left.and.right",
                    title: AppLocalization.string(model.hasLoaded ? "island.devices.empty" : "island.devices.loading"),
                    message: model.hasLoaded ? AppLocalization.string("island.devices.emptyMessage") : nil
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.devices) { device in
                            DeviceBatteryCard(device: device)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .islandScrollFade()
            }

            bluetoothAccessRow
        }
        .activatesIslandPanel(model)
    }

    /// Keyboards and mice on Bluetooth LE only report through Bluetooth
    /// access, which is asked for here instead of on launch.
    @ViewBuilder
    private var bluetoothAccessRow: some View {
        switch ble.access {
        case .notRequested:
            IslandChipButton(
                title: AppLocalization.string("island.devices.allowBluetooth"),
                systemImage: "computermouse"
            ) { model.requestBluetoothAccess() }
        case .denied:
            IslandChipButton(
                title: AppLocalization.string("island.devices.bluetoothDenied"),
                systemImage: "lock"
            ) { model.openBluetoothPrivacySettings() }
        case .allowed, .unavailable:
            EmptyView()
        }
    }
}

/// One AirPod or the case, shown as a small pill under the device name.
private struct BatteryComponent: Identifiable {
    let id: String
    let percent: Int
    let systemImage: String
    let label: String
}

/// Red at 20 % or less, like iOS; amber up to 40 %.
private enum BatteryTint {
    static func color(for percent: Int?) -> Color {
        guard let percent else { return IslandPalette.track }
        switch percent {
        case ...20: return Color(red: 1, green: 0.27, blue: 0.23)
        case ...40: return Color(red: 1, green: 0.74, blue: 0.2)
        default: return IslandPalette.accent
        }
    }
}

private struct DeviceBatteryCard: View {
    let device: DeviceBattery

    /// AirPods report left/right/case instead of one level.
    private var components: [BatteryComponent] {
        var parts: [BatteryComponent] = []
        if let left = device.left {
            parts.append(.init(id: "left", percent: left, systemImage: "airpod.left",
                               label: AppLocalization.string("island.devices.left")))
        }
        if let right = device.right {
            parts.append(.init(id: "right", percent: right, systemImage: "airpod.right",
                               label: AppLocalization.string("island.devices.right")))
        }
        if let caseLevel = device.caseLevel {
            parts.append(.init(id: "case", percent: caseLevel, systemImage: "airpodspro.chargingcase.wireless",
                               label: AppLocalization.string("island.devices.case")))
        }
        return parts
    }

    /// The ring shows the emptiest part, so a low AirPod isn't hidden.
    private var gaugeLevel: Int? {
        device.lowestLevel ?? device.caseLevel
    }

    private var isLow: Bool {
        (gaugeLevel ?? 100) <= 20
    }

    var body: some View {
        HStack(spacing: 12) {
            BatteryRing(percent: gaugeLevel, systemImage: device.kind.systemImage)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if gaugeLevel == nil {
                    Text(AppLocalization.string("island.devices.noLevel"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(IslandPalette.tertiaryText)
                } else if device.main != nil || components.isEmpty {
                    levelText
                    statusText
                } else {
                    statusText
                    componentPills
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(IslandPalette.cardStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var levelText: some View {
        Text(verbatim: "\(gaugeLevel ?? 0)")
            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
        + Text(verbatim: "%")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(IslandPalette.secondaryText)
    }

    private var statusText: some View {
        let kind = Text(AppLocalization.string(device.kind.titleKey))
            .foregroundStyle(IslandPalette.secondaryText)
        let status = Text(AppLocalization.string(isLow ? "island.devices.low" : "island.devices.ok"))
            .foregroundStyle(isLow ? BatteryTint.color(for: gaugeLevel) : IslandPalette.tertiaryText)
        return (kind + Text(verbatim: " · ").foregroundStyle(IslandPalette.tertiaryText) + status)
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
    }

    private var componentPills: some View {
        HStack(spacing: 4) {
            ForEach(components) { component in
                HStack(spacing: 3) {
                    Image(systemName: component.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(IslandPalette.secondaryText)
                    Text(verbatim: "\(component.percent)%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(component.percent <= 20 ? BatteryTint.color(for: component.percent) : .white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08), in: Capsule())
                .accessibilityLabel(Text(verbatim: "\(component.label) \(component.percent)%"))
            }
        }
        .padding(.top, 2)
    }

    /// A faint glow in the battery color behind the ring.
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(IslandPalette.card)
            .overlay(alignment: .leading) {
                RadialGradient(
                    colors: [BatteryTint.color(for: gaugeLevel).opacity(gaugeLevel == nil ? 0 : 0.16), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 60
                )
                .frame(width: 120, height: 120)
                .offset(x: -24)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Circular gauge in the battery color with the device's icon in the middle.
private struct BatteryRing: View {
    let percent: Int?
    let systemImage: String

    private static let size: CGFloat = 48
    private static let lineWidth: CGFloat = 4.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(IslandPalette.track, lineWidth: Self.lineWidth)
            if let percent {
                Circle()
                    .trim(from: 0, to: CGFloat(max(percent, 2)) / 100)
                    .stroke(BatteryTint.color(for: percent), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: BatteryTint.color(for: percent).opacity(0.45), radius: 4)
                    .animation(.easeOut(duration: 0.5), value: percent)
            }
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(percent == nil ? IslandPalette.tertiaryText : .white)
        }
        .frame(width: Self.size, height: Self.size)
    }
}
