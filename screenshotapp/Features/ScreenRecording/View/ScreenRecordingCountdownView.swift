import Combine
import SwiftUI

@MainActor
final class CountdownOverlayModel: ObservableObject {
    @Published var value: Int

    init(value: Int = 3) {
        self.value = value
    }
}

/// Full-screen, non-interactive 3-2-1 countdown shown before capture begins.
/// It is a DeskCast window, so it is excluded from the recording itself.
struct ScreenRecordingCountdownView: View {
    @ObservedObject var model: CountdownOverlayModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            Text("\(model.value)")
                .font(.system(size: 150, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 220, height: 220)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                .id(model.value)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.value)
        }
        .allowsHitTesting(false)
    }
}
