import SwiftUI

/// Floating controls shown under the area while it is being captured.
struct ScrollingCaptureControlsView: View {
    @ObservedObject var model: ScrollingCaptureViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(model.status == .lostTrack ? Color.orange : Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.string(statusKey))
                    .font(.system(size: 12, weight: .semibold))
                Text(AppLocalization.formatted("scrollCapture.height", Int(model.capturedHeight.rounded())))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 210, alignment: .leading)

            Button(AppLocalization.string("Cancel"), action: model.cancel)
            Button(AppLocalization.string("annotate.done"), action: model.finish)
                .buttonStyle(.borderedProminent)
                .disabled(model.phase != .capturing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .fixedSize()
    }

    private var statusKey: String {
        switch model.status {
        case .waitingForScroll: "scrollCapture.status.waiting"
        case .scrolling: "scrollCapture.status.scrolling"
        case .lostTrack: "scrollCapture.status.lostTrack"
        case .reachedLimit: "scrollCapture.status.limit"
        }
    }

    private var statusSymbol: String {
        switch model.status {
        case .waitingForScroll: "arrow.down.circle"
        case .scrolling: "scroll"
        case .lostTrack: "exclamationmark.triangle.fill"
        case .reachedLimit: "checkmark.circle.fill"
        }
    }
}

/// Dashed outline around the area being captured; it lets clicks and
/// scrolling through to the app underneath.
struct ScrollingCaptureOutlineView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            .allowsHitTesting(false)
    }
}
