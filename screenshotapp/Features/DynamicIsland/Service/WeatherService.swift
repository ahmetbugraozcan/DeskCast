import Foundation

nonisolated protocol WeatherProviding: Sendable {
    /// `language` (e.g. "tr") localizes the found place's name.
    func report(city: String, unit: WeatherUnit, language: String) async throws -> WeatherReport
}

/// Weather from Open-Meteo (open-meteo.com): free, no API key, no account.
/// The city typed in Settings is geocoded once (cached per name); only that
/// name and the found coordinates are sent — no location permission needed.
nonisolated final class OpenMeteoWeatherService: WeatherProviding, @unchecked Sendable {
    private let session: URLSession
    private let lock = NSLock()
    private var places: [String: WeatherPlace] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func report(city: String, unit: WeatherUnit, language: String) async throws -> WeatherReport {
        let place = try await place(for: city, language: language)

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m"
            ),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
            URLQueryItem(name: "wind_speed_unit", value: unit == .fahrenheit ? "mph" : "kmh")
        ]
        guard let url = components?.url else { throw WeatherError.badResponse }
        return try OpenMeteoParser.report(from: try await fetch(url), place: place, unit: unit)
    }

    private func place(for city: String, language: String) async throws -> WeatherPlace {
        let key = "\(language)|\(city.lowercased())"
        let cached = lock.withLock { places[key] }
        if let cached { return cached }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw WeatherError.badResponse }
        let place = try OpenMeteoParser.place(from: try await fetch(url))

        lock.withLock { places[key] = place }
        return place
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("DeskCast", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherError.badResponse }
        return data
    }
}
