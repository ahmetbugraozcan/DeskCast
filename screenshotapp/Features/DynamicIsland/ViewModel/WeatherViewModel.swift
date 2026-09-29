import Combine
import Foundation

/// Weather for the city set in Settings. Refreshes while the Weather panel is
/// on screen, and every 30 minutes in the background only while the closed
/// island shows the weather.
@MainActor
final class WeatherViewModel: ObservableObject, IslandPanelActivating {
    enum Failure: Equatable {
        case cityNotFound
        case unavailable
    }

    @Published private(set) var report: WeatherReport?
    @Published private(set) var isLoading = false
    @Published private(set) var failure: Failure?
    @Published private(set) var city = ""

    private let service: WeatherProviding
    private weak var island: DynamicIslandViewModel?
    private var unit = DynamicIslandSettings.defaultWeatherUnit
    private var showsInClosedIsland = false
    private var isPanelActive = false
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?
    private var settingsObserver: AnyCancellable?

    private static let refreshInterval: TimeInterval = 30 * 60
    /// Opening the panel refetches a report older than this.
    private static let staleAfter: TimeInterval = 10 * 60
    /// A report this old no longer shows in the closed island.
    private static let expiresAfter: TimeInterval = 3 * 60 * 60

    init(service: WeatherProviding = OpenMeteoWeatherService()) {
        self.service = service
    }

    func bind(to island: DynamicIslandViewModel) {
        self.island = island
        settingsObserver = island.$isEnabled
            .combineLatest(island.$preferences)
            .map { isEnabled, preferences in
                WeatherSettings(
                    city: preferences.weatherCity,
                    unit: preferences.weatherUnit,
                    showsInClosedIsland: isEnabled && [.weather, .automatic].contains(preferences.idleContent)
                )
            }
            .removeDuplicates()
            .sink { [weak self] settings in
                self?.apply(settings)
            }
    }

    func setActive(_ active: Bool) {
        isPanelActive = active
        if active, report.map({ Date().timeIntervalSince($0.fetchedAt) > Self.staleAfter }) ?? true {
            refresh()
        }
        updateTimer()
    }

    func refresh() {
        loadTask?.cancel()
        guard !city.isEmpty else {
            loadTask = nil
            isLoading = false
            return
        }

        isLoading = true
        let city = city
        let unit = unit
        let language = AppLocalization.currentLocale.language.languageCode?.identifier ?? "en"
        loadTask = Task { [weak self, service] in
            let result: Result<WeatherReport, Error>
            do {
                result = .success(try await service.report(city: city, unit: unit, language: language))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            self.finishLoading(result)
        }
    }

    private func finishLoading(_ result: Result<WeatherReport, Error>) {
        isLoading = false
        switch result {
        case .success(let report):
            self.report = report
            failure = nil
        case .failure(let error):
            failure = (error as? WeatherError) == .cityNotFound ? .cityNotFound : .unavailable
            if failure == .cityNotFound { report = nil }
            // Keep showing a recent report through a network hiccup.
            if let report, Date().timeIntervalSince(report.fetchedAt) > Self.expiresAfter { self.report = nil }
        }
        publishToIsland()
    }

    private func apply(_ settings: WeatherSettings) {
        let placeChanged = settings.city != city || settings.unit != unit
        city = settings.city
        unit = settings.unit
        showsInClosedIsland = settings.showsInClosedIsland

        if placeChanged {
            report = nil
            failure = nil
            if showsInClosedIsland || isPanelActive { refresh() } else { loadTask?.cancel() }
        } else if showsInClosedIsland, report == nil, !isLoading {
            refresh()
        }
        updateTimer()
        publishToIsland()
    }

    private func updateTimer() {
        let needsTimer = !city.isEmpty && (showsInClosedIsland || isPanelActive)
        guard needsTimer != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        guard needsTimer else { return }

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func publishToIsland() {
        island?.updateIdleWeather(showsInClosedIsland ? report : nil)
    }
}

private struct WeatherSettings: Equatable {
    let city: String
    let unit: WeatherUnit
    let showsInClosedIsland: Bool
}

enum WeatherFormat {
    /// "21°" — rounded, no unit letter, like the system weather.
    static func temperature(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    static func hour(_ date: Date, in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour()
        style.timeZone = timeZone
        style.locale = AppLocalization.currentLocale
        return date.formatted(style)
    }
}
