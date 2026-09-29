import SwiftUI

/// Closed island with a quick DeskCast confirmation: the symbol on the left
/// wing and the message on the right, so the island doesn't grow into a banner.
struct CompactToastView: View {
    let notification: DynamicIslandNotification
    let geometry: DynamicIslandGeometry

    var body: some View {
        let height = geometry.notchSize.height

        HStack(spacing: 8) {
            Image(systemName: notification.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(notification.style.tint)
                .symbolEffect(.bounce, options: .nonRepeating)
                .frame(width: height - 12)

            Spacer(minLength: geometry.hasNotch ? geometry.notchSize.width : 12)

            Text(notification.message ?? notification.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: DynamicIslandView.compactToastTextWidth, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(notification.message ?? notification.title))
    }
}
