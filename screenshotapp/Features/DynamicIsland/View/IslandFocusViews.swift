import SwiftUI

// MARK: - Focus

enum IslandFocusStyle {
    static let tint = Color(red: 0.55, green: 0.5, blue: 1)
}

/// Small moon beside another closed-island readout while a Focus is on.
struct IslandFocusMoon: View {
    var body: some View {
        Image(systemName: "moon.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(IslandFocusStyle.tint)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel(Text(AppLocalization.string("island.focus.on")))
    }
}

/// Closed island with nothing else to show while a Focus is on.
struct CompactFocusView: View {
    let geometry: DynamicIslandGeometry

    var body: some View {
        let height = geometry.notchSize.height

        HStack(spacing: 8) {
            Image(systemName: "moon.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandFocusStyle.tint)
                .symbolEffect(.bounce, options: .nonRepeating)
                .frame(width: height - 12)

            Spacer(minLength: geometry.hasNotch ? geometry.notchSize.width : 12)

            Text(AppLocalization.string("island.focus.label"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandFocusStyle.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppLocalization.string("island.focus.on")))
    }
}
