import AppKit
import Combine
import KeyboardShortcuts

/// Picks colors from the screen, copies them in the chosen format and keeps
/// a short list of recent colors.
@MainActor
final class ColorPickerViewModel: ObservableObject {
    @Published private(set) var recentColors: [PickedColor] = []
    @Published private(set) var isPicking = false

    private let sampler: ColorSampling
    private let settings: ToolboxSettingsReading
    private let toastPresenter: ToastPresenting
    private let defaults: UserDefaults

    init(
        sampler: ColorSampling,
        settings: ToolboxSettingsReading,
        toastPresenter: ToastPresenting,
        defaults: UserDefaults = .standard
    ) {
        self.sampler = sampler
        self.settings = settings
        self.toastPresenter = toastPresenter
        self.defaults = defaults
        ColorPickerSettings.registerDefaults(in: defaults)
        recentColors = (defaults.stringArray(forKey: ColorPickerSettings.Keys.recentColors) ?? [])
            .compactMap(PickedColor.init(hex:))

        KeyboardShortcuts.removeHandler(for: .pickColor)
        KeyboardShortcuts.onKeyUp(for: .pickColor) { [weak self] in
            Task { @MainActor in
                self?.pickColor()
            }
        }
    }

    deinit {
        KeyboardShortcuts.removeHandler(for: .pickColor)
    }

    var copyFormat: ColorCopyFormat {
        defaults.string(forKey: ColorPickerSettings.Keys.copyFormat).flatMap(ColorCopyFormat.init(rawValue:))
            ?? ColorPickerSettings.defaultCopyFormat
    }

    func pickColor() {
        guard settings.isToolEnabled(.pickColor), !isPicking else { return }

        isPicking = true
        sampler.sampleColor { [weak self] color in
            guard let self else { return }
            isPicking = false

            guard let color, let picked = PickedColor(color) else { return }

            remember(picked)
            copy(picked)
        }
    }

    func copy(_ color: PickedColor) {
        let text = color.formatted(copyFormat)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            NSSound.beep()
            toastPresenter.show(AppLocalization.string("Could not copy text"), systemImage: "exclamationmark.triangle.fill")
            return
        }

        toastPresenter.show(AppLocalization.formatted("colorPicker.copied", text), systemImage: "eyedropper.halffull")
    }

    func clearRecentColors() {
        recentColors = []
        saveRecents()
    }

    private func remember(_ color: PickedColor) {
        recentColors = ColorPickerSettings.updatedRecents(recentColors, adding: color)
        saveRecents()
    }

    private func saveRecents() {
        defaults.set(recentColors.map(\.hex), forKey: ColorPickerSettings.Keys.recentColors)
    }
}
