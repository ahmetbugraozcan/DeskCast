import Foundation
import Testing
@testable import screenshotapp

struct WeatherTests {
    private let place = WeatherPlace(name: "Istanbul", country: "Türkiye", latitude: 41.01, longitude: 28.95)

    @Test func parsesGeocodingResult() throws {
        let json = """
        {"results":[{"id":745044,"name":"İstanbul","latitude":41.01384,"longitude":28.94966,"country":"Türkiye"}]}
        """
        let found = try OpenMeteoParser.place(from: Data(json.utf8))
        #expect(found.name == "İstanbul")
        #expect(found.country == "Türkiye")
        #expect(abs(found.latitude - 41.01384) < 0.0001)
    }

    @Test func missingGeocodingResultsMeanCityNotFound() {
        #expect(throws: WeatherError.cityNotFound) {
            try OpenMeteoParser.place(from: Data(#"{"generationtime_ms":0.5}"#.utf8))
        }
    }

    @Test func parsesForecastAndStartsHourlyAtTheCurrentHour() throws {
        // 2026-09-29 12:00 UTC and the following hours.
        let start = 1_790_683_200
        let hours = (0..<30).map { start + $0 * 3600 }
        let json = """
        {"timezone":"Europe/Istanbul","utc_offset_seconds":10800,
         "current":{"temperature_2m":21.6,"apparent_temperature":20.1,"relative_humidity_2m":58,
                    "weather_code":2,"is_day":1,"wind_speed_10m":14.2},
         "hourly":{"time":\(hours),
                   "temperature_2m":\(hours.indices.map { 15.0 + Double($0) }),
                   "weather_code":\(hours.map { _ in 61 }),
                   "is_day":\(hours.map { _ in 0 }),
                   "precipitation_probability":\(hours.map { _ in 40 })},
         "daily":{"temperature_2m_max":[24.4,22.0],"temperature_2m_min":[15.2,14.0]}}
        """
        // Half past the third hour: that hour is still "now".
        let now = Date(timeIntervalSince1970: TimeInterval(start + 2 * 3600 + 1800))
        let report = try OpenMeteoParser.report(from: Data(json.utf8), place: place, unit: .celsius, now: now)

        #expect(report.temperature == 21.6)
        #expect(report.condition == .partlyCloudy && report.isDay)
        #expect(report.humidity == 58)
        #expect(report.high == 24.4 && report.low == 15.2)
        #expect(report.timeZone.identifier == "Europe/Istanbul")
        #expect(report.hourly.count == OpenMeteoParser.hourlyCount)
        #expect(report.hourly.first?.temperature == 17)
        #expect(report.hourly.first?.condition == .rain)
        #expect(report.hourly.first?.isDay == false)
        #expect(report.hourly.first?.precipitationChance == 40)
    }

    @Test func forecastWithoutCurrentConditionsIsRejected() {
        #expect(throws: WeatherError.badResponse) {
            try OpenMeteoParser.report(from: Data(#"{"hourly":{}}"#.utf8), place: place, unit: .celsius)
        }
    }

    @Test func mapsWMOCodes() {
        #expect(WeatherCondition(wmoCode: 0) == .clear)
        #expect(WeatherCondition(wmoCode: 3) == .overcast)
        #expect(WeatherCondition(wmoCode: 48) == .fog)
        #expect(WeatherCondition(wmoCode: 65) == .heavyRain)
        #expect(WeatherCondition(wmoCode: 67) == .freezingRain)
        #expect(WeatherCondition(wmoCode: 81) == .rainShowers)
        #expect(WeatherCondition(wmoCode: 99) == .thunderstorm)
        #expect(WeatherCondition(wmoCode: 1234) == .overcast)
        #expect(WeatherCondition.clear.systemImage(isDay: false) == "moon.stars.fill")
    }

    @Test func temperaturesRoundLikeTheSystemWeather() {
        #expect(WeatherFormat.temperature(21.6) == "22°")
        #expect(WeatherFormat.temperature(-0.4) == "0°")
        #expect(WeatherFormat.temperature(-3.5) == "-4°")
    }
}
