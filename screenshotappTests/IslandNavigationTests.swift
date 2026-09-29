import Foundation
import Testing
@testable import screenshotapp

@MainActor
struct IslandNavigationTests {
    private let presenter = FakeIslandPresenter()

    private func makeViewModel() -> DynamicIslandViewModel {
        let viewModel = DynamicIslandViewModel(
            nowPlayingService: FakeNowPlayingService(),
            batteryMonitor: FakeBatteryMonitor(),
            systemNotifications: FakeSystemNotificationMonitor(),
            settings: StubIslandSettings {
                $0.openMode = .hover
                $0.closeDelay = 0
            }
        )
        viewModel.presenter = presenter
        viewModel.start()
        return viewModel
    }

    /// A new page resizes the island, which can leave the pointer outside it.
    @Test func switchingPagesKeepsAHoverOpenedIslandOpen() async throws {
        let viewModel = makeViewModel()
        viewModel.setHovering(true)
        #expect(viewModel.mode == .expanded)

        viewModel.select(.weather)
        viewModel.setHovering(false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(viewModel.mode == .expanded)

        // Entering and leaving again closes it, like a click-open island.
        viewModel.setHovering(true)
        viewModel.setHovering(false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(viewModel.mode != .expanded)
    }
}
