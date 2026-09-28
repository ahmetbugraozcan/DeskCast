import AppKit
import CoreAudio
import SwiftUI

// MARK: - Now Playing

struct NowPlayingPanelView: View {
    @ObservedObject var store: DynamicIslandViewModel
    @ObservedObject var audio: AudioViewModel
    let namespace: Namespace.ID

    var body: some View {
        Group {
            if store.hasMedia, let nowPlaying = store.nowPlaying {
                content(nowPlaying)
            } else {
                emptyState
            }
        }
        .activatesIslandPanel(audio)
    }

    private func content(_ nowPlaying: NowPlayingInfo) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                Button {
                    store.openPlayer()
                } label: {
                    ArtworkView(nowPlaying: nowPlaying, cornerRadius: 16)
                        .frame(width: 118, height: 118)
                        .matchedGeometryEffect(id: "artwork", in: namespace)
                        .shadow(color: nowPlaying.tintColor.opacity(0.35), radius: 14, y: 4)
                }
                .buttonStyle(IslandScaleButtonStyle())
                .help(AppLocalization.formatted("Open %@", nowPlaying.player.displayName))

                VStack(alignment: .leading, spacing: 3) {
                    Text(nowPlaying.title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .contentTransition(.opacity)

                    Text(nowPlaying.artist.isEmpty ? nowPlaying.album : nowPlaying.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(IslandPalette.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    PlaybackProgressView(nowPlaying: nowPlaying)

                    HStack(spacing: 30) {
                        MediaControlButton(systemImage: "backward.end.fill", size: 17) {
                            store.previousTrack()
                        }
                        .help(AppLocalization.string("Previous Track"))

                        Button {
                            store.togglePlayPause()
                        } label: {
                            Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(.black)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(.white))
                                .contentShape(Circle())
                        }
                        .buttonStyle(IslandScaleButtonStyle())
                        .help(AppLocalization.string("Play / Pause"))

                        MediaControlButton(systemImage: "forward.end.fill", size: 17) {
                            store.nextTrack()
                        }
                        .help(AppLocalization.string("Next Track"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 118)
            }

            HStack(spacing: 10) {
                Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 18)
                    .onTapGesture { audio.toggleMute() }

                IslandSlider(value: audio.isMuted ? 0 : audio.volume) { audio.setVolume($0) }
                    .frame(height: 20)
                    .disabled(!audio.hasVolumeControl)

                OutputDeviceMenu(audio: audio)

                IslandChipButton(
                    title: AppLocalization.formatted("Open %@", nowPlaying.player.displayName),
                    systemImage: "arrow.up.forward.app"
                ) {
                    store.openPlayer()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            IslandEmptyState(
                systemImage: "music.note",
                title: AppLocalization.string("Nothing playing"),
                message: AppLocalization.string("Supported players: Music and Spotify. macOS asks once for permission to control them.")
            )

            HStack(spacing: 10) {
                ForEach(MediaPlayerApp.allCases) { player in
                    if let icon = player.appIcon {
                        Button {
                            store.openPlayer(player)
                        } label: {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(IslandScaleButtonStyle())
                        .help(AppLocalization.formatted("Open %@", player.displayName))
                    }
                }
            }
        }
    }
}

/// Horizontal drag slider in the island style (white fill on a dark track).
struct IslandSlider: View {
    let value: Double
    let onChange: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { proxy in
            let shown = dragValue ?? value

            ZStack(alignment: .leading) {
                Capsule().fill(IslandPalette.track)
                Capsule()
                    .fill(.white)
                    .frame(width: max(proxy.size.width * shown, proxy.size.height))
            }
            .frame(height: proxy.size.height)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = min(max(gesture.location.x / max(proxy.size.width, 1), 0), 1)
                        dragValue = newValue
                        onChange(newValue)
                    }
                    .onEnded { _ in dragValue = nil }
            )
            .animation(dragValue == nil ? .spring(response: 0.35, dampingFraction: 0.85) : nil, value: shown)
        }
    }
}

/// Tall slider used by the volume mixer.
struct IslandVerticalSlider: View {
    let value: Double
    let onChange: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { proxy in
            let shown = dragValue ?? value

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.16))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.92))
                    .frame(height: proxy.size.height * shown)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = 1 - gesture.location.y / max(proxy.size.height, 1)
                        let newValue = min(max(fraction, 0), 1)
                        dragValue = newValue
                        onChange(newValue)
                    }
                    .onEnded { _ in dragValue = nil }
            )
            .animation(dragValue == nil ? .spring(response: 0.35, dampingFraction: 0.85) : nil, value: shown)
        }
    }
}

struct OutputDeviceMenu: View {
    @ObservedObject var audio: AudioViewModel
    var showsName = false

    var body: some View {
        Menu {
            ForEach(audio.devices) { device in
                Button {
                    audio.selectDevice(device.id)
                } label: {
                    if device.id == audio.currentDeviceID {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if showsName {
                    Text(audio.currentDeviceName)
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Image(systemName: "airplayaudio")
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(audio.currentDeviceName)
    }
}

// MARK: - System

struct SystemPanelView: View {
    @ObservedObject var model: SystemStatsViewModel

    var body: some View {
        let stats = model.stats

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                percentCard(AppLocalization.string("island.system.cpu"), "cpu", stats.cpuUsage)
                percentCard(AppLocalization.string("island.system.gpu"), "display", stats.gpuUsage ?? 0)
                percentCard(AppLocalization.string("island.system.memory"), "memorychip", stats.memoryUsage)
            }

            HStack(spacing: 8) {
                IslandCard {
                    VStack(alignment: .leading, spacing: 6) {
                        IslandCardLabel(
                            title: AppLocalization.string("island.system.battery"),
                            systemImage: stats.isCharging ? "battery.100percent.bolt" : "battery.75percent"
                        )

                        if let level = stats.batteryLevel {
                            IslandRollingText(text: "\(level)%", value: Double(level))
                            IslandBar(value: Double(level) / 100, tint: level <= 20 && !stats.isPluggedIn ? .red : .white)
                        } else {
                            IslandRollingText(text: AppLocalization.string("island.system.acPower"), value: 0, size: 17)
                        }
                    }
                }

                IslandCard {
                    VStack(alignment: .leading, spacing: 4) {
                        IslandCardLabel(title: AppLocalization.string("island.system.network"), systemImage: "network")
                        IslandRollingText(
                            text: "↓ " + IslandFormat.rate(stats.downloadBytesPerSecond),
                            value: stats.downloadBytesPerSecond,
                            size: 18
                        )
                        Text("↑ " + IslandFormat.rate(stats.uploadBytesPerSecond))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(IslandPalette.secondaryText)
                            .contentTransition(.numericText(value: stats.uploadBytesPerSecond))
                            .animation(.snappy, value: stats.uploadBytesPerSecond)
                    }
                }
            }

            HStack(spacing: 8) {
                IslandCard {
                    VStack(alignment: .leading, spacing: 6) {
                        IslandCardLabel(title: AppLocalization.string("island.system.available"), systemImage: "internaldrive")
                        IslandRollingText(
                            text: IslandFormat.bytes(stats.diskAvailableBytes),
                            value: Double(stats.diskAvailableBytes / 1_000_000_000)
                        )
                        IslandBar(value: stats.diskAvailableFraction)
                    }
                }

                IslandCard {
                    VStack(alignment: .leading, spacing: 4) {
                        IslandCardLabel(title: AppLocalization.string("island.system.power"), systemImage: "powerplug")

                        if let watts = stats.systemPowerWatts {
                            IslandRollingText(text: "\(Int(watts.rounded()))W", value: watts.rounded(), size: 18)
                        } else {
                            IslandRollingText(text: "—", value: 0, size: 18)
                        }

                        if let adapter = stats.adapterWatts {
                            Text("\(adapter) W")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(IslandPalette.secondaryText)
                        }
                    }
                }
            }
        }
        .activatesIslandPanel(model)
    }

    private func percentCard(_ title: String, _ systemImage: String, _ value: Double) -> some View {
        IslandCard {
            VStack(alignment: .leading, spacing: 6) {
                IslandCardLabel(title: title, systemImage: systemImage)
                IslandRollingText(text: IslandFormat.percent(value), value: (value * 100).rounded())
                IslandBar(value: value, tint: value > 0.85 ? .orange : .white)
            }
        }
    }
}

// MARK: - Volume mixer

struct VolumePanelView: View {
    @ObservedObject var audio: AudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                OutputDeviceMenu(audio: audio, showsName: true)
                Spacer()
            }

            HStack(alignment: .top, spacing: 18) {
                mixerColumn(
                    systemImage: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    value: audio.isMuted ? 0 : audio.volume,
                    isEnabled: audio.hasVolumeControl,
                    onIconTap: { audio.toggleMute() },
                    onChange: { audio.setVolume($0) }
                )

                if let inputVolume = audio.inputVolume {
                    mixerColumn(
                        systemImage: audio.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill",
                        value: audio.isMicrophoneMuted ? 0 : inputVolume,
                        isEnabled: true,
                        onIconTap: { audio.toggleMicrophone() },
                        onChange: { audio.setInputVolume($0) }
                    )
                }

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.string("island.audio.outputs"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(IslandPalette.secondaryText)

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(audio.devices) { device in
                                deviceRow(device)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .activatesIslandPanel(audio)
    }

    private func mixerColumn(
        systemImage: String,
        value: Double,
        isEnabled: Bool,
        onIconTap: @escaping () -> Void,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Button(action: onIconTap) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 22)
            }
            .buttonStyle(IslandScaleButtonStyle())

            IslandVerticalSlider(value: value, onChange: onChange)
                .frame(width: 44)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.4)

            IslandRollingText(text: IslandFormat.percent(value), value: (value * 100).rounded(), size: 12, weight: .medium)
        }
    }

    private func deviceRow(_ device: AudioDevice) -> some View {
        let isCurrent = device.id == audio.currentDeviceID

        return Button {
            audio.selectDevice(device.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "speaker.wave.2.circle.fill" : "speaker.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isCurrent ? .white : IslandPalette.secondaryText)

                Text(device.name)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? .white : IslandPalette.secondaryText)
                    .lineLimit(1)

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isCurrent ? Color(white: 0.17) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isCurrent)
    }
}

// MARK: - AI agents

struct AIAgentsPanelView: View {
    @ObservedObject var model: AIUsageViewModel

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    AgentLimitsCard(
                        name: "Claude",
                        systemImage: "asterisk",
                        tint: IslandPalette.claude,
                        usage: model.report.claude,
                        sessionLength: 5 * 3600,
                        isLoading: !model.hasLoaded
                    )

                    AgentLimitsCard(
                        name: "Codex",
                        systemImage: "circle.hexagongrid.fill",
                        tint: IslandPalette.codex,
                        usage: model.report.codex,
                        sessionLength: 5 * 3600,
                        isLoading: !model.hasLoaded
                    )
                }
                .frame(height: 104)

                HStack(spacing: 8) {
                    spendCard
                    activityCard
                }
                .frame(height: 92)

                trendCard
                    .frame(height: 112)
            }
            .padding(.trailing, 4)
        }
        .activatesIslandPanel(model)
    }

    private var spendCard: some View {
        let spend = model.spend
        let cacheShare = spend.tokens > 0 ? Double(spend.cacheReadTokens) / Double(spend.tokens) : 0

        return IslandCard {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    IslandCardLabel(title: AppLocalization.string("island.ai.spend"), systemImage: "dollarsign.circle")
                    Spacer()
                    Menu {
                        ForEach(AIUsageViewModel.SpendPeriod.allCases) { period in
                            Button(AppLocalization.string("island.ai.period.\(period.rawValue)")) {
                                model.spendPeriod = period
                            }
                        }
                    } label: {
                        Text(AppLocalization.string("island.ai.period.\(model.spendPeriod.rawValue)"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    IslandRollingText(text: IslandFormat.currency(spend.cost), value: spend.cost, size: 22, weight: .bold)
                    Text(AppLocalization.string("island.ai.apiValue"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IslandPalette.secondaryText)
                }

                IslandBar(value: spend.cost > 0 ? 1 : 0, tint: IslandPalette.claude, height: 4)

                Text(AppLocalization.formatted(
                    "island.ai.tokensCache",
                    IslandFormat.tokens(spend.tokens),
                    IslandFormat.localizedPercent(cacheShare)
                ))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(IslandPalette.tertiaryText)
                .lineLimit(1)
            }
        }
    }

    private var activityCard: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: 8) {
                IslandCardLabel(title: AppLocalization.string("island.ai.now"), systemImage: "waveform.path.ecg")

                activityRow("Claude", "asterisk", IslandPalette.claude, model.report.claude.lastActivity)
                activityRow("Codex", "circle.hexagongrid.fill", IslandPalette.codex, model.report.codex.lastActivity)
            }
        }
    }

    private func activityRow(_ name: String, _ systemImage: String, _ tint: Color, _ date: Date?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Text(IslandFormat.relative(date))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(IslandPalette.secondaryText)
        }
    }

    private var trendCard: some View {
        let days = model.report.dailySpend
        let maxCost = max(days.map(\.cost).max() ?? 0, 0.01)
        let today = days.last

        return IslandCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IslandCardLabel(title: AppLocalization.string("island.ai.trend"), systemImage: "chart.bar")
                    Spacer()
                    if let today {
                        Text(AppLocalization.string("island.ai.period.today") + " · " + IslandFormat.currency(today.cost))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(IslandPalette.secondaryText)
                            .contentTransition(.numericText(value: today.cost))
                    }
                }

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(days) { day in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(day.id == today?.id ? IslandPalette.claude : IslandPalette.claude.opacity(0.35))
                                .frame(height: max(CGFloat(day.cost / maxCost) * 52, 3))
                                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: day.cost)

                            Text(day.day, format: .dateTime.weekday(.narrow))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(IslandPalette.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

private struct AgentLimitsCard: View {
    let name: String
    let systemImage: String
    let tint: Color
    let usage: AIAgentUsage
    let sessionLength: TimeInterval
    let isLoading: Bool

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                    Text(name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    if let plan = usage.plan {
                        Text(plan)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(tint.opacity(0.18)))
                    }
                }

                if usage.session != nil || usage.weekly != nil {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(spacing: 7) {
                            limitRow(
                                AppLocalization.string("island.ai.session"),
                                usage.session,
                                windowLength: sessionLength,
                                now: context.date
                            )
                            limitRow(
                                AppLocalization.string("island.ai.week"),
                                usage.weekly,
                                windowLength: 7 * 86_400,
                                now: context.date
                            )
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                    Text(isLoading ? AppLocalization.string("island.ai.loading") : unavailableText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IslandPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var unavailableText: String {
        switch usage.unavailableReason {
        case .notInstalled: AppLocalization.formatted("island.ai.notInstalled", name)
        case .tokenExpired: AppLocalization.formatted("island.ai.tokenExpired", name)
        case .requestFailed: AppLocalization.string("island.ai.requestFailed")
        case .signedOut, .none: AppLocalization.formatted("island.ai.signedOut", name)
        }
    }

    private func limitRow(_ title: String, _ window: AIUsageWindow?, windowLength: TimeInterval, now: Date) -> some View {
        let used = window?.usedFraction ?? 0
        // Marker: how far through the window we are, to compare pace vs. usage.
        let elapsed: Double? = window?.resetsAt.map { resetsAt in
            1 - min(max(resetsAt.timeIntervalSince(now) / windowLength, 0), 1)
        }

        return VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                if let countdown = IslandFormat.countdown(to: window?.resetsAt, from: now) {
                    Label(countdown, systemImage: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(IslandPalette.tertiaryText)
                        .labelStyle(.titleAndIcon)
                }

                Spacer()

                IslandRollingText(
                    text: IslandFormat.localizedPercent(used),
                    value: (used * 100).rounded(),
                    size: 12,
                    weight: .bold
                )
            }

            IslandBar(value: used, tint: tint, height: 6, marker: elapsed)
        }
    }
}
