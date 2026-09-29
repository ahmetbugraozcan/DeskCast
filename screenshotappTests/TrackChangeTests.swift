import Foundation
import Testing
@testable import screenshotapp

/// Like Vorssaint: playback goes straight to compact music, and the optional
/// new-song indicator is a brief peek in the wings, not a banner.
@MainActor
struct TrackChangeTests {
    private let nowPlaying = FakeNowPlayingService()
    private let presenter = FakeIslandPresenter()

    private func makeViewModel(settings: StubIslandSettings) -> DynamicIslandViewModel {
        let viewModel = DynamicIslandViewModel(
            nowPlayingService: nowPlaying,
            batteryMonitor: FakeBatteryMonitor(),
            systemNotifications: FakeSystemNotificationMonitor(),
            settings: settings
        )
        viewModel.presenter = presenter
        viewModel.start()
        return viewModel
    }

    @Test func trackChangesAreSilentByDefault() {
        let viewModel = makeViewModel(settings: StubIslandSettings())

        nowPlaying.emit(track("a"))
        nowPlaying.emit(track("b"))
        #expect(viewModel.activeNotification == nil)
        #expect(viewModel.mode == .compactMedia)
    }

    @Test func firstTrackIsSilentButTrackChangePeeksInTheWings() {
        let viewModel = makeViewModel(settings: StubIslandSettings { $0.showsTrackChanges = true })

        nowPlaying.emit(track("a"))
        #expect(viewModel.activeNotification == nil)

        nowPlaying.emit(track("b"))
        #expect(viewModel.mode == .compactToast)
        #expect(viewModel.activeNotification?.style == .media)
        #expect(viewModel.activeNotification?.title == "Title b")
    }
}
