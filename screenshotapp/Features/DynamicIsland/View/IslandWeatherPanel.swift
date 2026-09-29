import SwiftUI

// MARK: - Weather

/// Current conditions for the city set in Settings, plus the next 12 hours.
struct WeatherPanelView: View {
    @ObservedObject var model: WeatherViewModel
    let openSettings: () -> Void

    var body: some View {
        Group {
            if model.city.isEmpty {
                IslandEmptyState(
                    systemImage: "location.magnifyingglass",
                    title: AppLocalization.string("island.weather.noCity"),
                    message: AppLocalization.string("island.weather.noCityMessage"),
                    actionTitle: AppLocalization.string("island.weather.openSettings"),
                    action: openSettings
                )
            } else if let report = model.report {
                VStack(spacing: 10) {
                    WeatherSummaryCard(report: report)
                    HourlyForecastStrip(report: report)
                }
            } else if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                failureState
            }
        }
        .activatesIslandPanel(model)
    }

    private var failureState: some View {
        let notFound = model.failure == .cityNotFound
        return IslandEmptyState(
            systemImage: notFound ? "mappin.slash" : "wifi.exclamationmark",
            title: notFound
                ? AppLocalization.formatted("island.weather.cityNotFound", model.city)
                : AppLocalization.string("island.weather.unavailable"),
            message: AppLocalization.string(notFound ? "island.weather.cityNotFoundMessage" : "island.weather.unavailableMessage"),
            actionTitle: AppLocalization.string(notFound ? "island.weather.openSettings" : "island.weather.retry"),
            action: notFound ? openSettings : { model.refresh() }
        )
    }
}

private struct WeatherSummaryCard: View {
    let report: WeatherReport

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: report.systemImage)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 34))
                .frame(width: 44)

            Text(WeatherFormat.temperature(report.temperature))
                .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: report.temperature))

            VStack(alignment: .leading, spacing: 2) {
                Text(placeName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(AppLocalization.string(report.condition.titleKey))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandPalette.secondaryText)
                    .lineLimit(1)
                if let high = report.high, let low = report.low {
                    Text(AppLocalization.formatted(
                        "island.weather.highLow",
                        WeatherFormat.temperature(high),
                        WeatherFormat.temperature(low)
                    ))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(IslandPalette.tertiaryText)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 5) {
                if let feels = report.apparentTemperature {
                    detail("thermometer.medium", AppLocalization.formatted("island.weather.feelsLike", WeatherFormat.temperature(feels)))
                }
                if let humidity = report.humidity {
                    detail("humidity.fill", "\(humidity)%")
                }
                if let wind = report.windSpeed {
                    detail("wind", "\(Int(wind.rounded())) \(AppLocalization.string(report.unit == .fahrenheit ? "island.weather.mph" : "island.weather.kmh"))")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(IslandPalette.cardStroke, lineWidth: 1))
    }

    private var placeName: String {
        [report.place.name, report.place.country].compactMap(\.self).joined(separator: ", ")
    }

    /// Day: a faint blue sky; night: deep indigo.
    private var background: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: report.isDay
                        ? [Color(red: 0.16, green: 0.3, blue: 0.5).opacity(0.55), IslandPalette.card]
                        : [Color(red: 0.14, green: 0.12, blue: 0.32).opacity(0.6), IslandPalette.card],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func detail(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(IslandPalette.secondaryText)
                .frame(width: 13)
            Text(text)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

private struct HourlyForecastStrip: View {
    let report: WeatherReport

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(report.hourly.enumerated()), id: \.element.id) { index, hour in
                VStack(spacing: 5) {
                    Text(index == 0 ? AppLocalization.string("island.weather.now") : WeatherFormat.hour(hour.time, in: report.timeZone))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(index == 0 ? .white : IslandPalette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Image(systemName: hour.condition.systemImage(isDay: hour.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 15))
                        .frame(height: 18)

                    Text(WeatherFormat.temperature(hour.temperature))
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)

                    Text(chanceLabel(hour.precipitationChance))
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 1))
                        .frame(height: 10)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(IslandPalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(IslandPalette.cardStroke, lineWidth: 1))
    }

    /// Only a meaningful chance of rain is shown, like the system weather.
    private func chanceLabel(_ chance: Int?) -> String {
        guard let chance, chance >= 20 else { return "" }
        return "\(chance)%"
    }
}

// MARK: - Compact weather

/// Closed island: condition icon on the left wing, temperature on the right.
struct CompactWeatherView: View {
    let report: WeatherReport
    var showsFocus = false
    let geometry: DynamicIslandGeometry

    var body: some View {
        let height = geometry.notchSize.height

        HStack(spacing: 8) {
            Image(systemName: report.systemImage)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 13))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: height - 12)

            if showsFocus {
                IslandFocusMoon()
            }

            Spacer(minLength: geometry.hasNotch ? geometry.notchSize.width : 12)

            Text(WeatherFormat.temperature(report.temperature))
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: report.temperature))
                .animation(.snappy, value: report.temperature)
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(report.place.name), \(WeatherFormat.temperature(report.temperature)), \(AppLocalization.string(report.condition.titleKey))"))
    }
}
