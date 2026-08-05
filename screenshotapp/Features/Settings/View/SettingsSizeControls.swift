import SwiftUI

struct CustomThumbnailSizeControl: View {
    @Binding var width: Int
    let height: Int

    private var widthSliderValue: Binding<Double> {
        Binding {
            Double(width)
        } set: { newValue in
            width = ScreenshotShelfSettings.clampedCustomThumbnailWidth(Int(newValue.rounded()))
        }
    }

    var body: some View {
        Group {
            SettingsControlRow(title: AppLocalization.string("Dimensions")) {
                HStack(spacing: 8) {
                    TextField("", value: $width, format: .number)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)

                    Text(AppLocalization.formatted("x %ld px", height))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Stepper(
                        "",
                        value: $width,
                        in: ScreenshotShelfSettings.customThumbnailWidthRange
                    )
                    .labelsHidden()
                }
            }

            SettingsSectionDivider()

            SettingsControlRow(title: AppLocalization.string("Width")) {
                HStack(spacing: 8) {
                    Text("\(ScreenshotShelfSettings.customThumbnailWidthRange.lowerBound)")
                    Slider(
                        value: widthSliderValue,
                        in: Double(ScreenshotShelfSettings.customThumbnailWidthRange.lowerBound)...Double(ScreenshotShelfSettings.customThumbnailWidthRange.upperBound)
                    )
                    .frame(width: 190)
                    Text("\(ScreenshotShelfSettings.customThumbnailWidthRange.upperBound)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }
}

struct CustomAspectRatioControl: View {
    @Binding var width: Int
    @Binding var height: Int

    var body: some View {
        SettingsControlRow(title: AppLocalization.string("Ratio")) {
            HStack(spacing: 8) {
                TextField("", value: $width, format: .number)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)

                Text(":")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("", value: $height, format: .number)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

struct CustomDropShelfItemSizeControl: View {
    @Binding var width: Int
    let height: Int

    private var widthSliderValue: Binding<Double> {
        Binding {
            Double(width)
        } set: { newValue in
            width = DropShelfSettings.clampedCustomItemWidth(Int(newValue.rounded()))
        }
    }

    var body: some View {
        Group {
            SettingsControlRow(title: AppLocalization.string("Dimensions")) {
                HStack(spacing: 8) {
                    TextField("", value: $width, format: .number)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)

                    Text(AppLocalization.formatted("x %ld px", height))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Stepper(
                        "",
                        value: $width,
                        in: DropShelfSettings.customItemWidthRange
                    )
                    .labelsHidden()
                }
            }

            SettingsSectionDivider()

            SettingsControlRow(title: AppLocalization.string("Width")) {
                HStack(spacing: 8) {
                    Text("\(DropShelfSettings.customItemWidthRange.lowerBound)")
                    Slider(
                        value: widthSliderValue,
                        in: Double(DropShelfSettings.customItemWidthRange.lowerBound)...Double(DropShelfSettings.customItemWidthRange.upperBound)
                    )
                    .frame(width: 190)
                    Text("\(DropShelfSettings.customItemWidthRange.upperBound)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }
}
