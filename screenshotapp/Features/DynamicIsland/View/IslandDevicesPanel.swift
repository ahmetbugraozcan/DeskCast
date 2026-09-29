import SwiftUI

// MARK: - Devices

/// Battery levels of connected Bluetooth accessories: AirPods (left, right,
/// case), keyboards, mice and headphones.
struct DevicesPanelView: View {
    @ObservedObject var model: DevicesViewModel
    @ObservedObject var ble: BLEBatteryService

    init(model: DevicesViewModel) {
        self.model = model
        ble = model.ble
    }

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
                    LazyVStack(spacing: 6) {
                        ForEach(model.devices) { device in
                            DeviceBatteryRow(device: device)
                        }
                    }
                    .padding(.bottom, 6)
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

private struct DeviceBatteryRow: View {
    let device: DeviceBattery

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.kind.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(white: 0.2)))

            Text(device.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if device.hasBattery {
                HStack(spacing: 10) {
                    if let main = device.main { level(main, label: nil) }
                    if let left = device.left { level(left, label: AppLocalization.string("island.devices.left")) }
                    if let right = device.right { level(right, label: AppLocalization.string("island.devices.right")) }
                    if let caseLevel = device.caseLevel { level(caseLevel, label: AppLocalization.string("island.devices.case")) }
                }
            } else {
                Text(AppLocalization.string("island.devices.noLevel"))
                    .font(.system(size: 10))
                    .foregroundStyle(IslandPalette.tertiaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(IslandPalette.card))
    }

    private func level(_ percent: Int, label: String?) -> some View {
        HStack(spacing: 4) {
            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(IslandPalette.secondaryText)
            }
            BatteryGlyph(percent: percent)
            Text(verbatim: "\(percent)%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(percent <= 20 ? Color.red : .white)
        }
    }
}

/// Small battery outline filled to the level; red at 20 % or less.
private struct BatteryGlyph: View {
    let percent: Int

    var body: some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: 20, height: 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(percent <= 20 ? Color.red : IslandPalette.accent)
                        .frame(width: max(16 * CGFloat(percent) / 100, 1.5), height: 6)
                        .padding(.leading, 2)
                }
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color.white.opacity(0.5))
                .frame(width: 1.5, height: 4)
        }
        .accessibilityHidden(true)
    }
}
