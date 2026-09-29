import Combine
import Foundation

/// Mirrors "a Focus is on" into the island while the Focus indicator setting
/// is on. Polls, since macOS posts no Focus change notification to apps.
@MainActor
final class FocusIndicatorMonitor {
    private let service: FocusStatusProviding
    private weak var island: DynamicIslandViewModel?
    private var timer: Timer?
    private var settingsObserver: AnyCancellable?

    private static let pollInterval: TimeInterval = 2

    init(service: FocusStatusProviding? = nil) {
        self.service = service ?? SystemFocusStatusService()
    }

    func bind(to island: DynamicIslandViewModel) {
        self.island = island
        settingsObserver = island.$isEnabled
            .combineLatest(island.$preferences)
            .map { isEnabled, preferences in isEnabled && preferences.showsFocusIndicator }
            .removeDuplicates()
            .sink { [weak self] active in
                self?.setActive(active)
            }
    }

    private func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil

        guard active else {
            island?.updateFocusActive(false)
            return
        }

        // Keeps polling without access too, so allowing it in System
        // Settings takes effect without a restart.
        poll()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        island?.updateFocusActive(service.isFocused)
    }
}
