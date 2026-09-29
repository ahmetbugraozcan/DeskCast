import Foundation

/// Temperature unit for the island's weather.
nonisolated enum WeatherUnit: String, CaseIterable, Identifiable, Sendable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .celsius: "island.settings.weather.celsius"
        case .fahrenheit: "island.settings.weather.fahrenheit"
        }
    }

    /// Fahrenheit where the locale measures in US units.
    static var localeDefault: WeatherUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

/// WMO weather interpretation codes (as used by Open-Meteo), grouped into
/// what the island draws.
nonisolated enum WeatherCondition: String, Sendable, CaseIterable {
    case clear
    case mostlyClear
    case partlyCloudy
    case overcast
    case fog
    case drizzle
    case rain
    case heavyRain
    case freezingRain
    case snow
    case rainShowers
    case snowShowers
    case thunderstorm

    init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1: self = .mostlyClear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 61, 63: self = .rain
        case 65: self = .heavyRain
        case 56, 57, 66, 67: self = .freezingRain
        case 71, 73, 75, 77: self = .snow
        case 80, 81, 82: self = .rainShowers
        case 85, 86: self = .snowShowers
        case 95, 96, 99: self = .thunderstorm
        default: self = .overcast
        }
    }

    var titleKey: String { "island.weather.condition.\(rawValue)" }

    func systemImage(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .mostlyClear: isDay ? "sun.min.fill" : "moon.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .freezingRain: "cloud.sleet.fill"
        case .snow, .snowShowers: "cloud.snow.fill"
        case .rainShowers: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        }
    }
}

/// A place found by the geocoder for the city typed in Settings.
nonisolated struct WeatherPlace: Equatable, Sendable {
    let name: String
    let country: String?
    let latitude: Double
    let longitude: Double
}

nonisolated struct HourlyWeather: Identifiable, Equatable, Sendable {
    var id: Date { time }
    let time: Date
    let temperature: Double
    let condition: WeatherCondition
    let isDay: Bool
    /// Chance of precipitation in percent, when reported.
    let precipitationChance: Int?
}

nonisolated struct WeatherReport: Equatable, Sendable {
    let place: WeatherPlace
    let unit: WeatherUnit
    let temperature: Double
    let apparentTemperature: Double?
    let humidity: Int?
    let windSpeed: Double?
    let condition: WeatherCondition
    let isDay: Bool
    let high: Double?
    let low: Double?
    let timeZone: TimeZone
    let hourly: [HourlyWeather]
    let fetchedAt: Date

    var systemImage: String {
        condition.systemImage(isDay: isDay)
    }
}

nonisolated enum WeatherError: Error, Equatable {
    case cityNotFound
    case badResponse
}

/// Decodes Open-Meteo's geocoding and forecast responses (the forecast asked
/// with `timeformat=unixtime`).
nonisolated enum OpenMeteoParser {
    static let hourlyCount = 12

    static func place(from data: Data) throws -> WeatherPlace {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WeatherError.badResponse
        }
        guard let first = (root["results"] as? [[String: Any]])?.first,
              let name = first["name"] as? String,
              let latitude = number(first["latitude"]),
              let longitude = number(first["longitude"]) else {
            throw WeatherError.cityNotFound
        }
        return WeatherPlace(name: name, country: first["country"] as? String, latitude: latitude, longitude: longitude)
    }

    static func report(from data: Data, place: WeatherPlace, unit: WeatherUnit, now: Date = Date()) throws -> WeatherReport {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current"] as? [String: Any],
              let temperature = number(current["temperature_2m"]),
              let code = number(current["weather_code"]) else {
            throw WeatherError.badResponse
        }

        let daily = root["daily"] as? [String: Any]
        let offset = number(root["utc_offset_seconds"]).map { Int($0) } ?? 0
        let timeZone = (root["timezone"] as? String).flatMap(TimeZone.init(identifier:))
            ?? TimeZone(secondsFromGMT: offset) ?? .current

        return WeatherReport(
            place: place,
            unit: unit,
            temperature: temperature,
            apparentTemperature: number(current["apparent_temperature"]),
            humidity: number(current["relative_humidity_2m"]).map { Int($0.rounded()) },
            windSpeed: number(current["wind_speed_10m"]),
            condition: WeatherCondition(wmoCode: Int(code)),
            isDay: number(current["is_day"]).map { $0 != 0 } ?? true,
            high: (daily?["temperature_2m_max"] as? [Any])?.first.flatMap(number),
            low: (daily?["temperature_2m_min"] as? [Any])?.first.flatMap(number),
            timeZone: timeZone,
            hourly: hourly(from: root["hourly"] as? [String: Any], now: now),
            fetchedAt: now
        )
    }

    /// The next hours, starting with the one in progress.
    private static func hourly(from hourly: [String: Any]?, now: Date) -> [HourlyWeather] {
        guard let hourly,
              let times = hourly["time"] as? [Any],
              let temperatures = hourly["temperature_2m"] as? [Any],
              let codes = hourly["weather_code"] as? [Any] else { return [] }
        let isDay = hourly["is_day"] as? [Any] ?? []
        let chances = hourly["precipitation_probability"] as? [Any] ?? []

        var result: [HourlyWeather] = []
        for index in times.indices where index < temperatures.count && index < codes.count {
            guard let seconds = number(times[index]),
                  let temperature = number(temperatures[index]),
                  let code = number(codes[index]) else { continue }
            let time = Date(timeIntervalSince1970: seconds)
            guard time > now.addingTimeInterval(-3600) else { continue }
            result.append(HourlyWeather(
                time: time,
                temperature: temperature,
                condition: WeatherCondition(wmoCode: Int(code)),
                isDay: index < isDay.count ? number(isDay[index]).map { $0 != 0 } ?? true : true,
                precipitationChance: index < chances.count ? number(chances[index]).map { Int($0.rounded()) } : nil
            ))
            if result.count == hourlyCount { break }
        }
        return result
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
