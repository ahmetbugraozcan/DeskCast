import SwiftUI

struct ScreenRecordingControlView: View {
    /// The visible rounded card. The hosting window is larger by `shadowMargin`
    /// on every side so the SwiftUI shadow has room (the window itself draws none).
    static let contentSize = CGSize(width: 800, height: 60)
    static let shadowMargin: CGFloat = 16
    static let panelSize = CGSize(
        width: contentSize.width + shadowMargin * 2,
        height: contentSize.height + shadowMargin * 2
    )

    /// Shared height for every control on the row, so tops and bottoms line up.
    static let controlHeight: CGFloat = 38
    static let radius: CGFloat = 9
    static let itemSpacing: CGFloat = 8

    @ObservedObject var store: ScreenRecordingViewModel

    var body: some View {
        Group {
            if store.isRecording {
                recordingContent
            } else {
                setupContent
            }
        }
        .padding(.horizontal, 12)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
    }

    // MARK: - Setup

    private var setupContent: some View {
        HStack(spacing: Self.itemSpacing) {
            modeSegment

            groupDivider

            displayPicker

            if store.mode == .selectedArea {
                selectAreaButton
            }

            groupDivider

            audioMenu
            optionsMenu

            Spacer(minLength: 12)

            groupDivider

            recordButton
            closeButton
        }
        .frame(maxHeight: .infinity)
    }

    private var selectAreaButton: some View {
        Button(action: store.chooseSelectedArea) {
            Label(
                store.selectedArea == nil
                    ? AppLocalization.string("Select Area")
                    : selectedAreaLabel,
                systemImage: "viewfinder"
            )
        }
        .buttonStyle(RecorderControlStyle(isActive: store.selectedArea != nil))
        .fixedSize()
        .accessibilityLabel(Text(AppLocalization.string("Select Area")))
    }

    private var recordButton: some View {
        Button(action: store.startRecording) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.1))
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                Circle()
                    .fill(.red)
                    .frame(width: 20, height: 20)
                    .shadow(color: .red.opacity(0.5), radius: 5)
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(store.isPreparing || store.availableDisplays.isEmpty)
        .help(AppLocalization.string("Start Recording"))
        .accessibilityLabel(Text(AppLocalization.string("Start Recording")))
    }

    private var closeButton: some View {
        Button(action: store.hideRecorder) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(store.isPreparing)
        .accessibilityLabel(Text(AppLocalization.string("Close Recorder")))
    }

    // MARK: - Recording

    private var recordingContent: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.red.opacity(0.18)).frame(width: 30, height: 30)
                Circle()
                    .fill(.red)
                    .frame(width: 11, height: 11)
                    .shadow(color: .red.opacity(0.7), radius: 6)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(AppLocalization.string("Recording"))
                    .font(.system(size: 13.5, weight: .semibold))
                Text(recordingSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(Self.durationText(store.elapsedSeconds))
                .font(.system(size: 21, weight: .semibold, design: .monospaced))
                .monospacedDigit()

            Button(action: store.stopRecording) {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: 11, height: 11)
                    Text(AppLocalization.string("Stop"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .frame(height: Self.controlHeight)
                .background(.red, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(store.isPreparing)
            .accessibilityLabel(Text(AppLocalization.string("Stop Recording")))
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Mode segment

    private var modeSegment: some View {
        HStack(spacing: 3) {
            modeButton(.entireScreen, systemImage: "macwindow", title: AppLocalization.string("Full Screen"))
            modeButton(.selectedArea, systemImage: "viewfinder", title: AppLocalization.string("Area"))
        }
        .padding(3)
        .frame(height: Self.controlHeight)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: Self.radius + 2))
        // Keep the mode labels at their natural width so the variable-length
        // display name (below) is what gives way when the row gets tight.
        .fixedSize()
    }

    private func modeButton(_ mode: ScreenRecordingMode, systemImage: String, title: String) -> some View {
        let isSelected = store.mode == mode
        return Button {
            if mode == .selectedArea {
                store.enterAreaMode()
            } else {
                store.setMode(mode)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 11)
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: Self.radius - 2)
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    private var groupDivider: some View {
        Capsule()
            .fill(.white.opacity(0.1))
            .frame(width: 1, height: 22)
    }

    // MARK: - Menus

    private var displayPicker: some View {
        Menu {
            ForEach(store.availableDisplays) { display in
                Button {
                    store.selectDisplay(display.id)
                } label: {
                    Label(
                        display.name,
                        systemImage: display.id == store.selectedDisplayID ? "checkmark" : "display"
                    )
                }
            }
        } label: {
            Label(selectedDisplayName, systemImage: "display")
                .lineLimit(1)
        }
        .menuStyle(.button)
        .buttonStyle(RecorderControlStyle(isActive: false))
        .menuIndicator(.hidden)
        // No .fixedSize(): the display name is the row's flexible element, so an
        // unusually long name truncates here instead of squeezing the mode labels.
        .layoutPriority(-1)
        .accessibilityLabel(Text(AppLocalization.string("Display")))
    }

    private var audioMenu: some View {
        Menu {
            Toggle(
                AppLocalization.string("System Audio"),
                isOn: Binding(
                    get: { store.capturesSystemAudio },
                    set: store.setCapturesSystemAudio
                )
            )

            Toggle(
                AppLocalization.string("Microphone"),
                isOn: Binding(
                    get: { store.capturesMicrophone },
                    set: store.setCapturesMicrophone
                )
            )

            if store.capturesMicrophone {
                Divider()

                Button {
                    store.setMicrophoneDeviceID("")
                } label: {
                    Label(
                        AppLocalization.string("System Default"),
                        systemImage: store.microphoneDeviceID.isEmpty ? "checkmark" : "mic"
                    )
                }

                ForEach(store.availableMicrophones) { microphone in
                    Button {
                        store.setMicrophoneDeviceID(microphone.id)
                    } label: {
                        Label(
                            microphone.name,
                            systemImage: microphone.id == store.microphoneDeviceID ? "checkmark" : "mic"
                        )
                    }
                }
            }
        } label: {
            Image(systemName: store.capturesMicrophone ? "mic.fill" : "speaker.wave.2.fill")
        }
        .menuStyle(.button)
        .buttonStyle(RecorderControlStyle(isActive: store.capturesMicrophone, iconOnly: true))
        .menuIndicator(.hidden)
        .fixedSize()
        .help(AppLocalization.string("Audio"))
        .accessibilityLabel(Text(AppLocalization.string("Audio")))
    }

    private var optionsMenu: some View {
        Menu {
            Toggle(
                AppLocalization.string("Show Cursor"),
                isOn: Binding(get: { store.showsCursor }, set: store.setShowsCursor)
            )

            Toggle(
                AppLocalization.string("Show Mouse Clicks"),
                isOn: Binding(get: { store.showsMouseClicks }, set: store.setShowsMouseClicks)
            )

            Section(AppLocalization.string("Quality")) {
                ForEach(ScreenRecordingQuality.allCases) { quality in
                    Button {
                        store.setQuality(quality)
                    } label: {
                        Label(
                            Self.qualityTitle(quality),
                            systemImage: quality == store.quality ? "checkmark" : "gauge.with.dots.needle.67percent"
                        )
                    }
                }
            }

            Section(AppLocalization.string("Codec")) {
                ForEach(ScreenRecordingCodec.allCases) { codec in
                    Button {
                        store.setCodec(codec)
                    } label: {
                        Label(
                            Self.codecTitle(codec),
                            systemImage: codec == store.codec ? "checkmark" : "film"
                        )
                    }
                }
            }

            Section(AppLocalization.string("Frame rate")) {
                ForEach(ScreenRecordingFrameRate.allCases) { frameRate in
                    Button {
                        store.setFrameRate(frameRate)
                    } label: {
                        Label(
                            "\(frameRate.rawValue) FPS",
                            systemImage: frameRate == store.frameRate ? "checkmark" : "gauge.with.dots.needle.50percent"
                        )
                    }
                }
            }

            Section(AppLocalization.string("Countdown")) {
                ForEach(ScreenRecordingSettings.countdownOptions, id: \.self) { seconds in
                    Button {
                        store.setCountdownSeconds(seconds)
                    } label: {
                        Label(
                            Self.countdownTitle(seconds),
                            systemImage: seconds == store.countdownSeconds ? "checkmark" : "timer"
                        )
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuStyle(.button)
        .buttonStyle(RecorderControlStyle(isActive: false, iconOnly: true))
        .menuIndicator(.hidden)
        .fixedSize()
        .help(AppLocalization.string("Options"))
        .accessibilityLabel(Text(AppLocalization.string("Options")))
    }

    static func qualityTitle(_ quality: ScreenRecordingQuality) -> String {
        switch quality {
        case .high: AppLocalization.string("High")
        case .balanced: AppLocalization.string("Balanced")
        case .small: AppLocalization.string("Small File")
        }
    }

    static func codecTitle(_ codec: ScreenRecordingCodec) -> String {
        switch codec {
        case .h264: "H.264"
        case .hevc: "HEVC"
        }
    }

    static func countdownTitle(_ seconds: Int) -> String {
        seconds <= 0 ? AppLocalization.string("Off") : "\(seconds)s"
    }

    // MARK: - Helpers

    private var selectedDisplayName: String {
        store.availableDisplays.first { $0.id == store.selectedDisplayID }?.name
            ?? AppLocalization.string("Display")
    }

    private var selectedAreaLabel: String {
        guard let rect = store.selectedArea else { return AppLocalization.string("Select Area") }
        return "\(Int(rect.width)) × \(Int(rect.height))"
    }

    private var recordingSummary: String {
        let mode = store.mode == .entireScreen
            ? AppLocalization.string("Full Screen")
            : AppLocalization.string("Selected Area")
        return store.capturesMicrophone
            ? "\(mode) • \(AppLocalization.string("Microphone On"))"
            : mode
    }

    private static func durationText(_ totalSeconds: Int) -> String {
        String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct RecorderControlStyle: ButtonStyle {
    var isActive = false
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(isActive ? .white : .primary)
            .frame(
                width: iconOnly ? ScreenRecordingControlView.controlHeight : nil,
                height: ScreenRecordingControlView.controlHeight
            )
            .padding(.horizontal, iconOnly ? 0 : 12)
            .background(
                isActive ? Color.accentColor : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: ScreenRecordingControlView.radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ScreenRecordingControlView.radius)
                    .stroke(.white.opacity(isActive ? 0 : 0.08), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
