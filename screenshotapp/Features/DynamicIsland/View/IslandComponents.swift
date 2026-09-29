import AppKit
import SwiftUI

// Shared building blocks for the expanded island panels: dark rounded cards,
// numbers that roll when they change, and bars that glide to new values.

enum IslandPalette {
    static let card = Color(white: 0.105)
    static let cardStroke = Color.white.opacity(0.06)
    static let track = Color.white.opacity(0.14)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.38)
    static let accent = Color(red: 0.36, green: 0.86, blue: 0.52)
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codex = Color(red: 0.49, green: 0.55, blue: 0.96)
}

struct IslandCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(IslandPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(IslandPalette.cardStroke, lineWidth: 1)
            )
    }
}

/// Small icon + caption used as a card title ("CPU", "Ağ", …).
struct IslandCardLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(IslandPalette.secondaryText)
        .lineLimit(1)
    }
}

/// A value that rolls digit-by-digit when it changes.
struct IslandRollingText: View {
    let text: String
    let value: Double
    var size: CGFloat = 22
    var weight: Font.Weight = .semibold

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: value))
            .animation(.snappy(duration: 0.45), value: value)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Capsule progress bar that springs to its new value.
struct IslandBar: View {
    let value: Double
    var tint: Color = .white
    var height: CGFloat = 5
    /// Optional marker (e.g. elapsed share of a usage window).
    var marker: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(IslandPalette.track)

                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.width * min(max(value, 0), 1), value > 0 ? height : 0))

                if let marker {
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: 2, height: height + 6)
                        .offset(x: proxy.size.width * min(max(marker, 0), 1) - 1)
                }
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)
    }
}

/// Panel title row: title on the left, pin / collapse / extra controls on the right.
struct IslandPanelHeader<Trailing: View>: View {
    let title: String
    let isPinned: Bool
    let onPin: () -> Void
    let onCollapse: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.opacity)

            Spacer(minLength: 8)

            trailing

            IslandIconButton(
                systemImage: isPinned ? "pin.fill" : "pin",
                help: AppLocalization.string(isPinned ? "island.unpin" : "island.pin"),
                action: onPin
            )

            IslandIconButton(
                systemImage: "chevron.up",
                help: AppLocalization.string("island.collapse"),
                action: onCollapse
            )
        }
        .frame(height: 26)
    }
}

struct IslandIconButton: View {
    let systemImage: String
    var help: String?
    var size: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressButtonStyle())
        .help(help ?? "")
    }
}

/// Rounded pill button ("Şarkı sözleri"-style) used for secondary actions.
struct IslandChipButton: View {
    let title: String
    var systemImage: String?
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isOn ? .black : .white.opacity(0.85))
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(
                    Capsule().fill(isOn ? Color.white : Color.white.opacity(0.1))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

/// Square tile with an icon and caption (Controls / Tools grids).
struct IslandTileButton: View {
    let title: String
    let systemImage: String
    var subtitle: String?
    var tint: Color?
    var isOn = false
    /// Grids don't stretch their cells, so tiles carry their own height.
    var minHeight: CGFloat = 60
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isOn ? .black : (tint ?? .white))
                    .symbolEffect(.bounce, value: isOn)
                    // Symbols differ in height; a fixed box keeps titles on one line.
                    .frame(height: 22)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? .black : .white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isOn ? .black.opacity(0.55) : IslandPalette.tertiaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? Color.white : (isHovered ? Color(white: 0.16) : IslandPalette.card))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(IslandPalette.cardStroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(IslandScaleButtonStyle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
    }
}

struct IslandScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Empty state for panels that need data or a permission.
struct IslandEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(IslandPalette.secondaryText)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(IslandPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                IslandChipButton(title: actionTitle, systemImage: "arrow.right.circle", action: action)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Formatting

enum IslandFormat {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Turkish puts the sign first ("%83").
    static func localizedPercent(_ fraction: Double) -> String {
        let value = Int((fraction * 100).rounded())
        return AppLocalization.currentLanguage == .turkish ? "%\(value)" : "\(value)%"
    }

    /// "1:05.3" (or "1:02:05.3" past an hour), tenths of a second.
    static func stopwatch(_ interval: TimeInterval) -> String {
        let tenths = max(Int((interval * 10).rounded(.down)), 0)
        let seconds = tenths / 10
        let (hours, minutes) = (seconds / 3600, (seconds % 3600) / 60)

        return hours > 0
            ? String(format: "%d:%02d:%02d.%d", hours, minutes, seconds % 60, tenths % 10)
            : String(format: "%02d:%02d.%d", minutes, seconds % 60, tenths % 10)
    }

    static func bytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        // "0 KB/s", not "Zero KB/s".
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    static func tokens(_ count: Int) -> String {
        switch count {
        case 1_000_000...: String(format: "%.0fM", Double(count) / 1_000_000)
        case 1_000...: String(format: "%.0fK", Double(count) / 1_000)
        default: "\(count)"
        }
    }

    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(AppLocalization.currentLocale))
    }

    /// Compact countdown like "2sa 41d" / "2h 41m".
    static func countdown(to date: Date?, from now: Date = Date()) -> String? {
        guard let date else { return nil }

        let seconds = max(Int(date.timeIntervalSince(now)), 0)
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return AppLocalization.formatted("island.duration.dh", days, hours)
        }

        return AppLocalization.formatted("island.duration.hm", hours, minutes)
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded(.up)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = AppLocalization.currentLocale
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

extension View {
    /// Fades a scrolling list out at the bottom edge, so a row cut off by the
    /// panel reads as "more below" instead of clipped.
    func islandScrollFade(length: CGFloat = 18) -> some View {
        mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: length)
            }
        }
    }
}
