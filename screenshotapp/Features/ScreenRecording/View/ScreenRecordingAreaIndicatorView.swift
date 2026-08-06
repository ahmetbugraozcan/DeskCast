import SwiftUI

/// Non-interactive overlay that outlines the region being recorded. It is a
/// DeskCast window, so `SCContentFilter` excludes it from the capture — the user
/// sees the frame, but it never appears in the saved video.
struct ScreenRecordingAreaIndicatorView: View {
    private static let borderColor = Color(red: 0.98, green: 0.24, blue: 0.24)

    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .inset(by: 1.5)
            .stroke(Self.borderColor, lineWidth: 3)
            .shadow(color: Self.borderColor.opacity(0.55), radius: 6)
            .opacity(isPulsing ? 0.55 : 1)
            .overlay(alignment: .topLeading) {
                recordingBadge
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }

    private var recordingBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Self.borderColor)
                .frame(width: 7, height: 7)

            Text(AppLocalization.string("REC"))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.6), in: Capsule())
    }
}
