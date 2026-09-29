import AppKit
import SwiftUI

/// The expanded island: a header plus the selected panel (or the launcher grid).
/// Pages slide horizontally when switching so it reads as one continuous surface.
struct IslandExpandedView: View {
    @ObservedObject var store: DynamicIslandViewModel
    let panels: IslandPanelModels
    let geometry: DynamicIslandGeometry
    let namespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .top) {
            switch store.expandedContent {
            case .launcher:
                IslandLauncherView(store: store)
                    .transition(pageTransition)
            case .panel(let panel):
                panelView(panel)
                    .id(panel)
                    .transition(pageTransition)
            }
        }
        .padding(.top, geometry.notchSize.height + 4)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: store.expandedContent)
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.97, anchor: .top)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }

    @ViewBuilder
    private func panelView(_ panel: IslandPanel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IslandPanelHeader(
                title: AppLocalization.string(panel.titleKey),
                isPinned: store.isPinned,
                onPin: { store.togglePin() },
                onCollapse: { store.collapse() },
                trailing: { headerAccessory(for: panel) }
            )

            panelContent(panel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func sourceLabel(_ nowPlaying: NowPlayingInfo) -> some View {
        HStack(spacing: 5) {
            if let icon = nowPlaying.source.appIcon {
                // Menu labels ignore SwiftUI frames, so hand them a small bitmap.
                Image(nsImage: NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                    icon.draw(in: rect)
                    return true
                })
            }

            Text(nowPlaying.source.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IslandPalette.secondaryText)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func headerAccessory(for panel: IslandPanel) -> some View {
        switch panel {
        case .nowPlaying:
            if let nowPlaying = store.nowPlaying {
                // Other running players can be picked; otherwise just name the source.
                let others = store.availablePlayers.filter { $0 != nowPlaying.player }

                if others.isEmpty {
                    sourceLabel(nowPlaying)
                } else {
                    Menu {
                        ForEach(store.availablePlayers) { player in
                            Button(player.displayName) {
                                store.preferPlayer(player)
                            }
                        }
                    } label: {
                        sourceLabel(nowPlaying)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        case .notifications:
            if !store.notificationHistory.isEmpty {
                IslandIconButton(
                    systemImage: "trash",
                    help: AppLocalization.string("island.notifications.clear"),
                    action: { store.clearNotificationHistory() }
                )
            }
        case .timer:
            TimerModePicker(timer: panels.timer)
        case .clipboard:
            if !panels.clipboard.entries.isEmpty {
                IslandIconButton(
                    systemImage: "trash",
                    help: AppLocalization.string("island.clipboard.clear"),
                    action: { panels.clipboard.clear() }
                )
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func panelContent(_ panel: IslandPanel) -> some View {
        switch panel {
        case .controls:
            ControlsPanelView(controls: panels.controls, audio: panels.audio)
        case .volume:
            VolumePanelView(audio: panels.audio)
        case .nowPlaying:
            NowPlayingPanelView(
                store: store,
                audio: panels.audio,
                extras: panels.extras,
                namespace: namespace
            )
        case .captures:
            CapturesPanelView(shelf: panels.screenshots, actions: panels.actions)
        case .files:
            FilesPanelView(store: store, dropShelf: panels.dropShelf, actions: panels.actions)
        case .clipboard:
            ClipboardPanelView(model: panels.clipboard)
        case .system:
            SystemPanelView(model: panels.system)
        case .tools:
            ToolsPanelView(actions: panels.actions)
        case .calendar:
            CalendarPanelView(model: panels.calendar)
        case .notifications:
            NotificationsPanelView(store: store)
        case .timer:
            TimerPanelView(timer: panels.timer, stopwatch: panels.stopwatch)
        case .camera:
            CameraPanelView(model: panels.camera)
        case .downloads, .scratchpad, .aiAgents, .devices:
            utilityPanelContent(panel)
        }
    }

    /// Split from `panelContent` to keep each switch readable.
    @ViewBuilder
    private func utilityPanelContent(_ panel: IslandPanel) -> some View {
        switch panel {
        case .downloads:
            DownloadsPanelView(model: panels.downloads)
        case .scratchpad:
            ScratchpadPanelView()
        case .aiAgents:
            AIAgentsPanelView(model: panels.aiUsage)
        case .devices:
            DevicesPanelView(model: panels.devices)
        default:
            EmptyView()
        }
    }
}

/// Starts a panel model's polling while the panel is on screen.
struct IslandPanelActivation: ViewModifier {
    let model: IslandPanelActivating

    func body(content: Content) -> some View {
        content
            .onAppear { model.setActive(true) }
            .onDisappear { model.setActive(false) }
    }
}

extension View {
    func activatesIslandPanel(_ model: IslandPanelActivating) -> some View {
        modifier(IslandPanelActivation(model: model))
    }
}

// MARK: - Compact timer

struct CompactTimerView: View {
    @ObservedObject var timer: IslandTimerViewModel
    let geometry: DynamicIslandGeometry

    var body: some View {
        let height = geometry.notchSize.height

        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: timer.progress(at: context.date))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: timer.progress(at: context.date))
                }
                .frame(width: height - 14, height: height - 14)

                Spacer(minLength: geometry.hasNotch ? geometry.notchSize.width : 12)

                Text(IslandFormat.clock(timer.remaining(at: context.date)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(timer.isPaused ? .white.opacity(0.5) : .orange)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: Int(timer.remaining(at: context.date)))
            }
            .padding(.horizontal, 10)
            .frame(height: height)
        }
    }
}

/// Closed-island battery readout ("While idle: Battery").
struct CompactBatteryView: View {
    let status: BatteryStatus
    let geometry: DynamicIslandGeometry

    var body: some View {
        let height = geometry.notchSize.height
        let isLow = status.level <= 20 && !status.isPluggedIn
        let tint: Color = status.isPluggedIn ? .green : (isLow ? .red : .white)

        HStack(spacing: 8) {
            Image(systemName: status.isPluggedIn ? "bolt.fill" : "battery.75percent")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: height - 12)

            Spacer(minLength: geometry.hasNotch ? geometry.notchSize.width : 12)

            Text("\(status.level)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText(value: Double(status.level)))
                .animation(.snappy, value: status.level)
        }
        .padding(.horizontal, 10)
        .frame(height: height)
    }
}
