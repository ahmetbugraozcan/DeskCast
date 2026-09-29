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

/// One component's level: the whole device, or an AirPod / the case.
private struct BatteryComponent: Identifiable {
    let id: String
    let percent: Int
    let systemImage: String
    let label: String?
}

private struct DeviceBatteryCard: View {
    let device: DeviceBattery

    private var components: [BatteryComponent] {
        var parts: [BatteryComponent] = []
        if let main = device.main {
            parts.append(.init(id: "main", percent: main, systemImage: device.kind.systemImage, label: nil))
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: device.kind.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandPalette.secondaryText)
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            if components.isEmpty {
                HStack(spacing: 8) {
                    BatteryRing(percent: nil, systemImage: device.kind.systemImage)
                    Text(AppLocalization.string("island.devices.noLevel"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(IslandPalette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if components.count == 1, let only = components.first {
                HStack(spacing: 10) {
                    BatteryRing(percent: only.percent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.string(device.kind.titleKey))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(AppLocalization.string(only.percent <= 20 ? "island.devices.low" : "island.devices.ok"))
                            .font(.system(size: 10))
                            .foregroundStyle(only.percent <= 20 ? Color(red: 1, green: 0.4, blue: 0.35) : IslandPalette.tertiaryText)
                    }
                }
            } else {
                HStack(spacing: 14) {
                    ForEach(components) { component in
                        VStack(spacing: 4) {
                            BatteryRing(percent: component.percent, systemImage: component.label == nil ? nil : component.systemImage)
                            if let label = component.label {
                                Text(label)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(IslandPalette.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IslandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(IslandPalette.cardStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Circular gauge with the percentage in the middle (or an icon when the
/// device reports no level). Red at 20 % or less, like iOS.
private struct BatteryRing: View {
    let percent: Int?
    var systemImage: String?

    private static let size: CGFloat = 44
    private static let lineWidth: CGFloat = 4

    private var tint: Color {
        guard let percent else { return IslandPalette.track }
        return percent <= 20 ? Color(red: 1, green: 0.27, blue: 0.23) : IslandPalette.accent
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(IslandPalette.track, lineWidth: Self.lineWidth)
            if let percent {
                Circle()
                    .trim(from: 0, to: CGFloat(max(percent, 2)) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: percent)
                VStack(spacing: 0) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(IslandPalette.secondaryText)
                    }
                    Text(verbatim: "\(percent)")
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    + Text(verbatim: "%")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(IslandPalette.secondaryText)
                }
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(IslandPalette.tertiaryText)
            }
        }
        .frame(width: Self.size, height: Self.size)
    }
}
