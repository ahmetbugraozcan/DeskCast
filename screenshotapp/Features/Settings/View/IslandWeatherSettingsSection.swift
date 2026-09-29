import SwiftUI

/// City and unit for the island's weather. The city is saved on Return or when
/// the field loses focus, so typing doesn't look up every partial name.
struct IslandWeatherSettingsSection: View {
    @AppStorage(DynamicIslandSettings.Keys.weatherCity)
    private var weatherCity = ""
    @AppStorage(DynamicIslandSettings.Keys.weatherUnit)
    private var weatherUnit = DynamicIslandSettings.defaultWeatherUnit

    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        SettingsControlSection(title: AppLocalization.string("island.settings.weather")) {
            SettingsControlRow(title: AppLocalization.string("island.settings.weather.city")) {
                TextField(AppLocalization.string("island.settings.weather.cityPlaceholder"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .focused($isFieldFocused)
                    .onSubmit(save)
                    .onChange(of: isFieldFocused) { _, focused in
                        if !focused { save() }
                    }
            }

            SettingsSectionDivider()

            SettingsSegmentedRow(title: AppLocalization.string("island.settings.weather.unit")) {
                Picker("", selection: $weatherUnit) {
                    ForEach(WeatherUnit.allCases) { unit in
                        Text(AppLocalization.string(unit.titleKey)).tag(unit)
                    }
                }
            }

            Text(AppLocalization.string("island.settings.weather.hint"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { draft = weatherCity }
        .onChange(of: weatherCity) { _, city in
            if !isFieldFocused { draft = city }
        }
    }

    private func save() {
        let city = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = city
        if city != weatherCity { weatherCity = city }
    }
}
