import AppKit
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

            Spacer(minLength: geometry.hasNotch ? geometry.notchSize.width : 0)

            Text(Self.text(of: notification))
                .font(.system(size: Self.fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Self.textWidth(Self.text(of: notification)), alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.text(of: notification)))
    }

    private static let fontSize: CGFloat = 12
    /// Longer messages (file names) are shortened in the middle.
    private static let maxTextWidth: CGFloat = 150

    static func text(of notification: DynamicIslandNotification) -> String {
        notification.message ?? notification.title
    }

    /// The message's width on the right wing, which sizes the island.
    static func textWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return min(ceil(width) + 2, maxTextWidth)
    }
}
