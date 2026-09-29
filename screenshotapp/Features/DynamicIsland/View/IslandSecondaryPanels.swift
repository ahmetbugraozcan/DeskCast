import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Controls

struct ControlsPanelView: View {
    @ObservedObject var controls: ControlsViewModel
    @ObservedObject var audio: AudioViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                IslandTileButton(
                    title: AppLocalization.string("island.controls.darkMode"),
                    systemImage: controls.isDarkMode ? "moon.fill" : "sun.max.fill",
                    isOn: controls.isDarkMode
                ) { controls.toggleDarkMode() }

                IslandTileButton(
                    title: AppLocalization.string("island.controls.keepAwake"),
                    systemImage: "cup.and.saucer.fill",
                    isOn: controls.isKeepingAwake
                ) { controls.toggleKeepAwake() }

                IslandTileButton(
                    title: AppLocalization.string("island.controls.mute"),
                    systemImage: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    isOn: audio.isMuted
                ) { audio.toggleMute() }

                IslandTileButton(
                    title: AppLocalization.string("island.controls.microphone"),
                    systemImage: audio.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill",
                    isOn: audio.isMicrophoneMuted
                ) { audio.toggleMicrophone() }

                IslandTileButton(
                    title: AppLocalization.string("island.controls.displaySleep"),
                    systemImage: "display"
                ) { controls.sleepDisplay() }

                IslandTileButton(
                    title: AppLocalization.string("island.controls.screenSaver"),
                    systemImage: "sparkles.tv"
                ) { controls.startScreenSaver() }

                IslandTileButton(
                    title: AppLocalization.string("island.controls.systemSettings"),
                    systemImage: "gearshape.2"
                ) { controls.openSystemSettings() }

                IslandTileButton(
                    title: audio.currentDeviceName,
                    systemImage: "hifispeaker.fill"
                ) {
                    // Cycle to the next output device.
                    guard let index = audio.devices.firstIndex(where: { $0.id == audio.currentDeviceID }),
                          audio.devices.count > 1
                    else { return }
                    audio.selectDevice(audio.devices[(index + 1) % audio.devices.count].id)
                }
            }
            .frame(height: 136)

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(IslandPalette.secondaryText)
                IslandSlider(value: audio.isMuted ? 0 : audio.volume) { audio.setVolume($0) }
                    .frame(height: 20)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(IslandPalette.secondaryText)
            }
        }
        .activatesIslandPanel(controls)
        .activatesIslandPanel(audio)
    }
}

// MARK: - Captures

struct CapturesPanelView: View {
    @ObservedObject var shelf: ScreenshotShelfViewModel
    let actions: IslandToolActions

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                IslandTileButton(
                    title: AppLocalization.string("island.tools.captureArea"),
                    systemImage: "camera.viewfinder"
                ) { actions.captureArea() }

                IslandTileButton(
                    title: AppLocalization.string("island.tools.captureVideo"),
                    systemImage: "record.circle"
                ) { actions.captureVideo() }
            }
            .frame(width: 104)

            if shelf.screenshots.isEmpty {
                IslandEmptyState(
                    systemImage: "photo.on.rectangle",
                    title: AppLocalization.string("island.captures.empty"),
                    message: AppLocalization.string("island.captures.emptyMessage")
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelf.screenshots.reversed()) { item in
                            captureThumbnail(item)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shelf.screenshots.map(\.id))
                }
            }
        }
    }

    private func captureThumbnail(_ item: ScreenshotItem) -> some View {
        Button {
            shelf.copy(item)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: item.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if item.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(IslandPalette.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(IslandScaleButtonStyle())
        .help(AppLocalization.string("island.captures.copyHint"))
        .onDrag {
            if let url = item.fileURL {
                return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: item.image)
            }

            return NSItemProvider(object: item.image)
        }
        .contextMenu {
            Button(AppLocalization.string("island.captures.copy")) { shelf.copy(item) }
            if item.fileURL != nil {
                Button(AppLocalization.string("island.captures.reveal")) { shelf.showInFinder(item) }
            }
            Button(AppLocalization.string("island.captures.remove"), role: .destructive) { shelf.remove(item) }
        }
    }
}

// MARK: - Files (Drop Shelf)

struct FilesPanelView: View {
    @ObservedObject var store: DynamicIslandViewModel
    @ObservedObject var dropShelf: DropShelfViewModel
    let actions: IslandToolActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dropShelf.items.isEmpty {
                IslandEmptyState(
                    systemImage: "tray.and.arrow.down",
                    title: AppLocalization.string("island.files.empty"),
                    message: AppLocalization.string("island.files.emptyMessage")
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dropShelf.items) { item in
                            fileTile(item)
                        }
                    }
                }
                .frame(height: 112)
            }

            HStack(spacing: 8) {
                IslandChipButton(title: AppLocalization.string("island.files.add"), systemImage: "plus") {
                    chooseFiles()
                }

                IslandChipButton(
                    title: AppLocalization.string(dropShelf.isShelfVisible ? "Hide Drop Shelf" : "Show Drop Shelf"),
                    systemImage: "tray.and.arrow.down",
                    isOn: dropShelf.isShelfVisible
                ) { actions.toggleDropShelf() }

                if !dropShelf.items.isEmpty {
                    IslandChipButton(title: AppLocalization.string("Send Shelf Items"), systemImage: "paperplane") {
                        dropShelf.sendAll()
                    }

                    IslandChipButton(title: AppLocalization.string("Clear Drop Shelf"), systemImage: "trash") {
                        dropShelf.clearAll()
                    }
                }

                Spacer()
            }
        }
    }

    /// The island stays open behind the open panel so the new files show up in it.
    private func chooseFiles() {
        let urls = store.holdingOpen { () -> [URL] in
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.prompt = AppLocalization.string("island.files.addPrompt")
            NSApp.activate()
            return panel.runModal() == .OK ? panel.urls : []
        }

        dropShelf.addFiles(urls, revealsShelf: false)
    }

    private func fileTile(_ item: DropShelfItem) -> some View {
        Button {
            dropShelf.preview(item)
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let image = item.image {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else if let url = item.fileURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
                    } else {
                        Image(systemName: item.url != nil ? "link" : "text.alignleft")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(item.displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 96, height: 108)
            .background(IslandPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(IslandScaleButtonStyle())
        .onDrag {
            if let url = item.fileURL ?? item.url {
                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
            }

            if let text = item.text {
                return NSItemProvider(object: text as NSString)
            }

            return NSItemProvider()
        }
    }
}

// MARK: - Tools

struct ToolsPanelView: View {
    let actions: IslandToolActions

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            IslandTileButton(title: AppLocalization.string("island.tools.captureArea"), systemImage: "camera.viewfinder", minHeight: 72) {
                actions.captureArea()
            }
            IslandTileButton(
                title: AppLocalization.string("island.tools.captureVideo"),
                systemImage: "record.circle",
                tint: .red,
                minHeight: 72
            ) {
                actions.captureVideo()
            }
            IslandTileButton(title: AppLocalization.string("island.tools.captureText"), systemImage: "text.viewfinder", minHeight: 72) {
                actions.captureText()
            }
            IslandTileButton(title: AppLocalization.string("island.tools.finderPath"), systemImage: "folder", minHeight: 72) {
                actions.copyFinderPath()
            }
            IslandTileButton(title: AppLocalization.string("island.tools.dropShelf"), systemImage: "tray.and.arrow.down", minHeight: 72) {
                actions.toggleDropShelf()
            }
            IslandTileButton(title: AppLocalization.string("Settings"), systemImage: "gearshape", minHeight: 72) {
                actions.openSettings()
            }
        }
        .frame(height: 156)
    }
}

// MARK: - Calendar

struct CalendarPanelView: View {
    @ObservedObject var model: CalendarViewModel

    var body: some View {
        Group {
            switch model.accessState {
            case .granted:
                content
            case .notDetermined:
                IslandEmptyState(
                    systemImage: "calendar",
                    title: AppLocalization.string("island.calendar.accessTitle"),
                    message: AppLocalization.string("island.calendar.accessMessage"),
                    actionTitle: AppLocalization.string("island.calendar.allow"),
                    action: { model.requestAccess() }
                )
            case .denied:
                IslandEmptyState(
                    systemImage: "calendar.badge.exclamationmark",
                    title: AppLocalization.string("island.calendar.deniedTitle"),
                    message: AppLocalization.string("island.calendar.deniedMessage"),
                    actionTitle: AppLocalization.string("island.openSettings"),
                    action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
        }
        .activatesIslandPanel(model)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            IslandCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Date(), format: .dateTime.weekday(.wide))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.3, blue: 0.3))
                        .textCase(.uppercase)

                    Text(Date(), format: .dateTime.day())
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 4) {
                        ForEach(model.week, id: \.self) { day in
                            dayCell(day)
                        }
                    }
                }
            }
            .frame(width: 220)
            .onTapGesture { model.openCalendar() }

            VStack(alignment: .leading, spacing: 6) {
                if model.events.isEmpty {
                    IslandEmptyState(
                        systemImage: "checkmark.circle",
                        title: AppLocalization.string("island.calendar.noEvents")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(model.events) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)

        return VStack(spacing: 3) {
            Text(day, format: .dateTime.weekday(.narrow))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(IslandPalette.tertiaryText)

            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 11, weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? .black : .white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isToday ? Color.white : Color.clear))

            Circle()
                .fill(model.daysWithEvents.contains(calendar.startOfDay(for: day)) ? Color(red: 1, green: 0.3, blue: 0.3) : .clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func eventRow(_ event: IslandCalendarEvent) -> some View {
        HStack(spacing: 9) {
            Capsule()
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Group {
                    if event.isAllDay {
                        Text(AppLocalization.string("island.calendar.allDay"))
                    } else {
                        let locale = AppLocalization.currentLocale
                        let start = event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(locale))
                        let end = event.end.formatted(.dateTime.hour().minute().locale(locale))
                        Text(verbatim: "\(start) – \(end)")
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(IslandPalette.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(IslandPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Notifications

struct NotificationsPanelView: View {
    @ObservedObject var store: DynamicIslandViewModel

    var body: some View {
        if store.notificationHistory.isEmpty {
            IslandEmptyState(
                systemImage: "bell.slash",
                title: AppLocalization.string("island.notifications.empty"),
                message: AppLocalization.string("island.notifications.emptyMessage")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.notificationHistory) { notification in
                        row(notification)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.notificationHistory.map(\.id))
            }
        }
    }

    private func row(_ notification: DynamicIslandNotification) -> some View {
        Button {
            if let url = notification.sourceAppURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let image = notification.image {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: notification.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(notification.style.tint)
                    }
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(notification.caption ?? notification.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(IslandPalette.tertiaryText)
                            .textCase(.uppercase)
                            .lineLimit(1)
                        Spacer()
                        Text(notification.date, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(IslandPalette.tertiaryText)
                    }

                    if notification.caption != nil {
                        Text(notification.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    if let message = notification.message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(IslandPalette.secondaryText)
                            .lineLimit(2)
                    }
                }
            }
            .padding(9)
            .background(IslandPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Camera mirror

struct CameraPanelView: View {
    @ObservedObject var model: CameraMirrorViewModel

    var body: some View {
        Group {
            switch model.authorization {
            case .authorized:
                CameraPreviewView(session: model.preview.session)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(IslandPalette.cardStroke, lineWidth: 1)
                    )
            case .notDetermined:
                IslandEmptyState(
                    systemImage: "web.camera",
                    title: AppLocalization.string("island.camera.accessTitle"),
                    message: AppLocalization.string("island.camera.accessMessage"),
                    actionTitle: AppLocalization.string("island.camera.allow"),
                    action: { model.requestAccess() }
                )
            default:
                IslandEmptyState(
                    systemImage: "video.slash",
                    title: AppLocalization.string("island.camera.deniedTitle"),
                    actionTitle: AppLocalization.string("island.openSettings"),
                    action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
        }
        .activatesIslandPanel(model)
    }
}

/// Mirrored live camera preview.
private struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        previewLayer.frame = view.bounds
        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        previewLayer.connection?.isVideoMirrored = true
        view.layer = previewLayer

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Downloads

struct DownloadsPanelView: View {
    @ObservedObject var model: DownloadsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.files.isEmpty {
                IslandEmptyState(systemImage: "arrow.down.circle", title: AppLocalization.string("island.downloads.empty"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.files) { file in
                            row(file)
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.files.map(\.id))
                }
            }

            HStack {
                Spacer()
                IslandChipButton(title: AppLocalization.string("island.downloads.openFolder"), systemImage: "folder") {
                    model.openFolder()
                }
            }
        }
        .activatesIslandPanel(model)
    }

    private func row(_ file: DownloadedFile) -> some View {
        Button {
            model.open(file)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                    .resizable()
                    .frame(width: 26, height: 26)

                Text(file.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let size = file.size {
                    Text(IslandFormat.bytes(size))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(IslandPalette.tertiaryText)
                }

                Text(IslandFormat.relative(file.date))
                    .font(.system(size: 10.5))
                    .foregroundStyle(IslandPalette.secondaryText)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(IslandPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
        .contextMenu {
            Button(AppLocalization.string("island.captures.reveal")) { model.reveal(file) }
        }
    }
}

// MARK: - Scratchpad

struct ScratchpadPanelView: View {
    @AppStorage(DynamicIslandSettings.Keys.scratchpadText) private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(8)

            if text.isEmpty {
                Text(AppLocalization.string("island.scratchpad.placeholder"))
                    .font(.system(size: 13))
                    .foregroundStyle(IslandPalette.tertiaryText)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .background(IslandPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Text(AppLocalization.formatted("island.scratchpad.count", text.count))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(IslandPalette.tertiaryText)
                .contentTransition(.numericText(value: Double(text.count)))
                .animation(.snappy, value: text.count)
                .padding(8)
        }
    }
}
