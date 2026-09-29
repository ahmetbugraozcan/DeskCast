import AppKit
import SwiftUI

/// Where the island and its floating side buttons sit inside the panel, in
/// SwiftUI (top-left origin) coordinates. The coordinator converts these frames
/// to screen space for hover and click hit-testing, so view and hit area share
/// one source of truth.
struct DynamicIslandLayout: Equatable {
    let panelSize: CGSize
    let islandFrame: CGRect
    let orbFrames: [DynamicIslandOrb: CGRect]
    var chipFrames: [IslandActivityChip: CGRect] = [:]

    var interactiveFrames: [CGRect] {
        [islandFrame] + orbFrames.values + chipFrames.values
    }
}

/// Round buttons floating beside the expanded island.
enum DynamicIslandOrb: CaseIterable, Hashable {
    case launcher
    case timer
    case settings
    case volume
    case nowPlaying

    var systemImage: String {
        switch self {
        case .launcher: "square.grid.2x2"
        case .timer: "timer"
        case .settings: "gearshape"
        case .volume: "speaker.wave.2"
        case .nowPlaying: "music.note"
        }
    }
}

/// Notch-anchored "Dynamic Island". The panel is a fixed, transparent canvas; the
/// island shape inside it morphs between modes with a spring so AppKit never has
/// to animate the window frame.
struct DynamicIslandView: View {
    @ObservedObject var store: DynamicIslandViewModel
    let panels: IslandPanelModels
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let shadowPadding: CGFloat = 26
    static let hoverGrowScale: CGFloat = 1.06
    static let expandedMinimumWidth: CGFloat = 560
    static let notificationContentHeight: CGFloat = 60
    static let notificationMinimumWidth: CGFloat = 380
    static let orbSize: CGFloat = 40
    static let orbGap: CGFloat = 12
    static let chipSize = CGSize(width: 104, height: 28)
    static let chipGap: CGFloat = 8

    static let morphAnimation = Animation.spring(response: 0.42, dampingFraction: 0.78)

    // MARK: - Metrics

    /// Content height below the notch for each expanded page.
    static func expandedContentHeight(for content: IslandExpandedContent) -> CGFloat {
        switch content {
        case .launcher: 300
        case .panel(let panel): panelContentHeights[panel] ?? 260
        }
    }

    private static let panelContentHeights: [IslandPanel: CGFloat] = [
        .controls: 212,
        .volume: 262,
        .nowPlaying: 214,
        .captures: 196,
        .files: 208,
        .clipboard: 262,
        .system: 300,
        .tools: 196,
        .calendar: 244,
        .notifications: 262,
        .timer: 214,
        .camera: 290,
        .downloads: 262,
        .scratchpad: 224,
        .aiAgents: 300,
        .devices: 244,
        .weather: 214
    ]

    private static var maxExpandedContentHeight: CGFloat {
        IslandPanel.allCases.map { expandedContentHeight(for: .panel($0)) }.max() ?? 300
    }

    private static func expandedWidth(for geometry: DynamicIslandGeometry) -> CGFloat {
        max(expandedMinimumWidth, geometry.notchSize.width + 220)
    }

    static func panelSize(for geometry: DynamicIslandGeometry) -> CGSize {
        let islandWidth = expandedWidth(for: geometry) + cornerMetrics(for: .expanded).top * 2
        let orbColumns = (orbSize + orbGap) * 2

        return CGSize(
            width: islandWidth + orbColumns + shadowPadding * 2,
            height: geometry.notchSize.height + maxExpandedContentHeight + orbGap + orbSize + shadowPadding
        )
    }

    static func layout(for store: DynamicIslandViewModel) -> DynamicIslandLayout {
        let mode = store.mode
        let geometry = store.geometry
        let panelSize = panelSize(for: geometry)
        let size = islandSize(
            for: mode,
            content: store.expandedContent,
            geometry: geometry,
            hasMedia: store.hasMedia,
            combinesTimer: store.showsTimerBeside,
            toastText: store.activeNotification.map(CompactToastView.text(of:))
        )
        let islandFrame = CGRect(
            x: ((panelSize.width - size.width) / 2).rounded(),
            y: 0,
            width: size.width,
            height: size.height
        )

        var orbs: [DynamicIslandOrb: CGRect] = [:]
        let chips = activityChipFrames(for: store, below: islandFrame)

        if mode == .expanded, store.preferences.showsSideButtons {
            let ears = cornerMetrics(for: .expanded).top
            let leftX = islandFrame.minX + ears - orbGap - orbSize
            let rightX = islandFrame.maxX - ears + orbGap
            let firstY = geometry.notchSize.height + 14
            let secondY = firstY + orbSize + orbGap

            orbs[.launcher] = CGRect(x: leftX, y: firstY, width: orbSize, height: orbSize)
            orbs[.timer] = CGRect(x: leftX, y: secondY, width: orbSize, height: orbSize)
            orbs[.settings] = CGRect(x: rightX, y: firstY, width: orbSize, height: orbSize)
            orbs[.volume] = CGRect(x: rightX, y: secondY, width: orbSize, height: orbSize)

            // The activity chips take the spot under the island.
            if store.expandedContent != .panel(.nowPlaying), chips.isEmpty {
                orbs[.nowPlaying] = CGRect(
                    x: islandFrame.midX - orbSize / 2,
                    y: islandFrame.maxY + orbGap,
                    width: orbSize,
                    height: orbSize
                )
            }
        }

        return DynamicIslandLayout(panelSize: panelSize, islandFrame: islandFrame, orbFrames: orbs, chipFrames: chips)
    }

    /// A centered row of chips under the island: each activity going on,
    /// then "automatic".
    private static func activityChipFrames(for store: DynamicIslandViewModel, below islandFrame: CGRect) -> [IslandActivityChip: CGRect] {
        guard store.showsActivityPicker else { return [:] }

        let chips = store.availableActivities.map(IslandActivityChip.activity) + [.automatic]
        let rowWidth = CGFloat(chips.count) * chipSize.width + CGFloat(chips.count - 1) * chipGap
        // The hovered closed island swells a little, so leave it room.
        let top = islandFrame.maxY + (store.mode == .expanded ? orbGap : islandFrame.height * (hoverGrowScale - 1) + chipGap)
        var frames: [IslandActivityChip: CGRect] = [:]

        for (index, chip) in chips.enumerated() {
            frames[chip] = CGRect(
                x: (islandFrame.midX - rowWidth / 2 + CGFloat(index) * (chipSize.width + chipGap)).rounded(),
                y: top,
                width: chipSize.width,
                height: chipSize.height
            )
        }

        return frames
    }

    /// Full island frame for a mode, including the flared top "ears".
    static func islandSize(
        for mode: DynamicIslandMode,
        content: IslandExpandedContent,
        geometry: DynamicIslandGeometry,
        hasMedia: Bool,
        combinesTimer: Bool = false,
        toastText: String? = nil
    ) -> CGSize {
        let notch = geometry.notchSize
        let ears = cornerMetrics(for: mode).top * 2

        switch mode {
        case .idle:
            return CGSize(width: notch.width + ears, height: notch.height)
        case .compactToast where !geometry.hasNotch:
            // No camera housing to clear: symbol and message side by side.
            let content = (notch.height - 12) + 8 + CompactToastView.textWidth(toastText ?? "") + 20
            return CGSize(width: content + ears, height: notch.height)
        case .compactMedia, .compactTimer, .compactBattery, .compactWeather, .compactFocus, .compactAgent, .compactToast:
            // Music with a running timer shows the countdown on the right wing.
            let sideWidth = switch mode {
            case .compactMedia where !combinesTimer: notch.height + 18
            // The right wing fits the message, so it sits next to the notch.
            case .compactToast: max(CompactToastView.textWidth(toastText ?? "") + 20, notch.height + 18)
            default: notch.height + 34
            }
            let centerWidth = geometry.hasNotch ? notch.width : max(notch.width, 220)
            return CGSize(width: centerWidth + sideWidth * 2 + ears, height: notch.height)
        case .notification:
            return CGSize(
                width: max(notificationMinimumWidth, notch.width + 160) + ears,
                height: notch.height + notificationContentHeight
            )
        case .expanded:
            return CGSize(
                width: expandedWidth(for: geometry) + ears,
                height: notch.height + expandedContentHeight(for: content)
            )
        }
    }

    static func cornerMetrics(for mode: DynamicIslandMode) -> (top: CGFloat, bottom: CGFloat) {
        switch mode {
        case .idle: return (top: 6, bottom: 9)
        case .compactMedia, .compactTimer, .compactBattery, .compactWeather, .compactFocus, .compactAgent, .compactToast:
            return (top: 6, bottom: 13)
        case .notification: return (top: 12, bottom: 24)
        case .expanded: return (top: 14, bottom: 30)
        }
    }

    // MARK: - Body

    var body: some View {
        let mode = store.mode
        let geometry = store.geometry
        let layout = Self.layout(for: store)
        let corners = Self.cornerMetrics(for: mode)
        let shape = DynamicIslandShape(topCornerRadius: corners.top, bottomCornerRadius: corners.bottom)
        // "Hidden until hover" is the only mode that hides the closed island,
        // also on displays without a notch.
        let isShapeVisible = !store.hidesCollapsedIsland
        // The closed island swells slightly under the pointer before it opens.
        let growsOnHover = store.isHovering && !reduceMotion && (mode == .idle || mode.isCompact)

        ZStack(alignment: .topLeading) {
            ZStack(alignment: .top) {
                content(for: mode, geometry: geometry)
                    .padding(.horizontal, corners.top)
            }
            .frame(width: layout.islandFrame.width, height: layout.islandFrame.height, alignment: .top)
            .background(Color.black)
            .clipShape(shape)
            .overlay {
                if store.preferences.showsOutline, mode != .idle {
                    shape.stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
            }
            .contentShape(shape)
            .shadow(color: .black.opacity(mode == .idle ? 0 : 0.38), radius: mode == .expanded ? 18 : 10, y: 6)
            .opacity(isShapeVisible ? 1 : 0)
            .scaleEffect(growsOnHover ? Self.hoverGrowScale : 1, anchor: .top)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: growsOnHover)
            .onTapGesture {
                store.handleTap()
            }
            .offset(x: layout.islandFrame.minX, y: layout.islandFrame.minY)

            ForEach(DynamicIslandOrb.allCases, id: \.self) { orb in
                if let frame = layout.orbFrames[orb] {
                    IslandOrbButton(orb: orb, isSelected: isOrbSelected(orb)) {
                        handleOrb(orb)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }

            ForEach(IslandActivityChip.allCases, id: \.self) { chip in
                if let frame = layout.chipFrames[chip] {
                    IslandActivityChipButton(chip: chip, store: store)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
                }
            }
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .topLeading)
        .animation(Self.morphAnimation, value: mode)
        .animation(Self.morphAnimation, value: layout)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, AppLocalization.currentLocale)
    }

    private func isOrbSelected(_ orb: DynamicIslandOrb) -> Bool {
        switch orb {
        case .launcher: store.expandedContent == .launcher
        case .timer: store.expandedContent == .panel(.timer)
        case .volume: store.expandedContent == .panel(.volume)
        case .nowPlaying, .settings: false
        }
    }

    private func handleOrb(_ orb: DynamicIslandOrb) {
        switch orb {
        case .launcher: store.showLauncher()
        case .timer: store.select(.timer)
        case .volume: store.select(.volume)
        case .nowPlaying: store.select(.nowPlaying)
        case .settings:
            store.collapse()
            panels.actions.openSettings()
        }
    }

    @ViewBuilder
    private func content(for mode: DynamicIslandMode, geometry: DynamicIslandGeometry) -> some View {
        switch mode {
        case .idle:
            Color.clear
        case .compactMedia:
            if let nowPlaying = store.nowPlaying {
                CompactMediaView(
                    nowPlaying: nowPlaying,
                    timer: store.timer,
                    showsTimer: store.showsTimerBeside,
                    showsFocus: store.isFocusActive,
                    geometry: geometry,
                    namespace: namespace
                )
                .transition(Self.contentTransition)
            }
        case .compactTimer:
            CompactTimerView(timer: store.timer, showsFocus: store.isFocusActive, geometry: geometry)
                .transition(Self.contentTransition)
        case .compactBattery:
            if let status = store.batteryStatus {
                CompactBatteryView(status: status, showsFocus: store.isFocusActive, geometry: geometry)
                    .transition(Self.contentTransition)
            }
        case .compactWeather:
            if let weather = store.idleWeather {
                CompactWeatherView(report: weather, showsFocus: store.isFocusActive, geometry: geometry)
                    .transition(Self.contentTransition)
            }
        case .compactFocus:
            CompactFocusView(geometry: geometry)
                .transition(Self.contentTransition)
        case .compactAgent:
            CompactAgentView(
                sessions: store.agentSessions,
                timer: store.timer,
                showsTimer: store.showsTimerBeside,
                showsFocus: store.isFocusActive,
                geometry: geometry
            )
            .transition(Self.contentTransition)
        case .compactToast:
            if let notification = store.activeNotification {
                CompactToastView(notification: notification, geometry: geometry)
                    .id(notification.id)
                    .transition(Self.contentTransition)
            }
        case .notification:
            if let notification = store.activeNotification {
                NotificationBannerView(notification: notification, geometry: geometry) { url in
                    NSWorkspace.shared.open(url)
                    store.dismissNotification()
                }
                    .id(notification.id)
                    .transition(Self.contentTransition)
            }
        case .expanded:
            IslandExpandedView(store: store, panels: panels, geometry: geometry, namespace: namespace)
                .transition(Self.contentTransition)
        }
    }

    static var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.86, anchor: .top))
                .animation(morphAnimation.delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }
}

private struct IslandOrbButton: View {
    let orb: DynamicIslandOrb
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: orb.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: DynamicIslandView.orbSize, height: DynamicIslandView.orbSize)
                .background(Circle().fill(isSelected ? Color(white: 0.22) : Color.black))
                .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressButtonStyle())
    }
}

// MARK: - Shape

/// Notch silhouette: concave flares at the top edge that melt into the menu
/// bar, and rounded bottom corners. Both radii animate.
struct DynamicIslandShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topCornerRadius, rect.width / 4)
        let bottom = min(bottomCornerRadius, (rect.width - top * 2) / 2, rect.height - top)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Compact

struct CompactMediaView: View {
    let nowPlaying: NowPlayingInfo
    @ObservedObject var timer: IslandTimerViewModel
    /// A running timer shares the right wing (automatic activities).
    var showsTimer = false
    var showsFocus = false
    let geometry: DynamicIslandGeometry
    let namespace: Namespace.ID

    var body: some View {
        let height = geometry.notchSize.height

        HStack(spacing: 8) {
            ArtworkView(nowPlaying: nowPlaying, cornerRadius: 6)
                .frame(width: height - 12, height: height - 12)
                .matchedGeometryEffect(id: "artwork", in: namespace)

            // Without a hardware notch the middle is visible, so show the title.
            if geometry.hasNotch {
                Spacer(minLength: geometry.notchSize.width)
            } else {
                Text(nowPlaying.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }

            if showsTimer {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(IslandFormat.clock(timer.remaining(at: context.date)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.isPaused ? .white.opacity(0.5) : .orange)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: Int(timer.remaining(at: context.date)))
                }
                .transition(.opacity)
            } else {
                if showsFocus {
                    IslandFocusMoon()
                }
                EqualizerBarsView(isPlaying: nowPlaying.isPlaying, tint: nowPlaying.tintColor)
                    .frame(width: 18, height: 13)
                    .matchedGeometryEffect(id: "equalizer", in: namespace)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
    }
}

struct PlaybackProgressView: View {
    let nowPlaying: NowPlayingInfo
    /// Enables scrubbing; called with the target position when the drag ends.
    var onSeek: ((TimeInterval) -> Void)?

    @State private var scrubFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = scrubFraction ?? nowPlaying.progress(at: context.date)
            let elapsed = scrubFraction.map { $0 * nowPlaying.duration } ?? nowPlaying.elapsed(at: context.date)

            HStack(spacing: 10) {
                Text(Self.format(elapsed))
                    .frame(width: 38, alignment: .leading)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.16))

                        Capsule()
                            .fill(nowPlaying.tintColor)
                            .frame(width: max(proxy.size.width * progress, 4))
                            .animation(scrubFraction == nil ? .linear(duration: 1) : nil, value: progress)
                    }
                    .frame(height: scrubFraction == nil ? 4 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(scrubGesture(width: proxy.size.width), including: canSeek ? .all : .none)
                }
                .frame(height: 12)
                .animation(.easeOut(duration: 0.15), value: scrubFraction == nil)

                Text(nowPlaying.duration > 0 ? "-" + Self.format(nowPlaying.duration - elapsed) : "--:--")
                    .frame(width: 42, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var canSeek: Bool {
        onSeek != nil && nowPlaying.duration > 0
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                scrubFraction = min(max(gesture.location.x / max(width, 1), 0), 1)
            }
            .onEnded { _ in
                if let scrubFraction {
                    onSeek?(scrubFraction * nowPlaying.duration)
                }
                scrubFraction = nil
            }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Notification

struct NotificationBannerView: View {
    let notification: DynamicIslandNotification
    let geometry: DynamicIslandGeometry
    var performAction: (URL) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                if let caption = notification.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .textCase(.uppercase)
                        .lineLimit(1)
                }

                Text(notification.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let message = notification.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let action = notification.action {
                Button {
                    performAction(action.url)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.green, in: Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
            } else if let progress = notification.progress {
                ProgressRingView(progress: progress, tint: notification.style.tint)
                    .frame(width: 26, height: 26)
            } else if notification.style == .media {
                EqualizerBarsView(isPlaying: true, tint: notification.style.tint)
                    .frame(width: 18, height: 14)
            }
        }
        .padding(.top, geometry.notchSize.height + 2)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = notification.image {
            // Clip after framing: a wide video thumbnail filled without a frame
            // spills past the square onto the text.
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: notification.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(notification.style.tint)
                .symbolEffect(.bounce, value: notification.id)
                .frame(width: 36, height: 36)
                .background(notification.style.tint.opacity(0.18), in: Circle())
        }
    }
}

struct ProgressRingView: View {
    let progress: Double
    let tint: Color
    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 3)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) {
                animatedProgress = progress
            }
        }
    }
}

// MARK: - Shared pieces

struct ArtworkView: View {
    let nowPlaying: NowPlayingInfo
    let cornerRadius: CGFloat

    var body: some View {
        // `Color.clear` takes the offered frame, so wide covers (videos) are
        // cropped to it instead of widening the view.
        Color.clear
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: nowPlaying.artwork != nil)
    }

    private var content: some View {
        ZStack {
            if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                LinearGradient(
                    colors: [nowPlaying.tintColor.opacity(0.7), nowPlaying.tintColor.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// Four capsules bouncing on offset sine waves while playing; they settle into
/// short dots when paused.
struct EqualizerBarsView: View {
    let isPlaying: Bool
    let tint: Color

    private static let speeds: [Double] = [7.1, 9.3, 6.2, 8.4]
    private static let phases: [Double] = [0, 1.7, 3.1, 4.4]

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            GeometryReader { proxy in
                let barWidth = max((proxy.size.width - 6) / 4, 2)

                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(tint)
                            .frame(width: barWidth, height: barHeight(index: index, time: time, maxHeight: proxy.size.height))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPlaying)
    }

    private func barHeight(index: Int, time: TimeInterval, maxHeight: CGFloat) -> CGFloat {
        let minHeight = min(3, maxHeight)

        guard isPlaying else { return minHeight }

        let wave = (sin(time * Self.speeds[index] + Self.phases[index]) + 1) / 2
        let secondary = (sin(time * Self.speeds[index] * 0.47 + Self.phases[index] * 2) + 1) / 2
        let level = 0.25 + 0.75 * (wave * 0.7 + secondary * 0.3)
        return max(minHeight, maxHeight * level)
    }
}

struct MediaControlButton: View {
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 18, height: size + 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressButtonStyle())
    }
}

struct IslandPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IslandPressButtonBody(configuration: configuration)
    }
}

/// Separate view so the hover highlight can keep its own `@State`.
struct IslandPressButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.2 : (isHovered ? 0.1 : 0)))
                    .padding(-2)
            )
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension NowPlayingInfo {
    var tintColor: Color {
        artworkTint.map(Color.init(nsColor:)) ?? Color(red: 0.36, green: 0.86, blue: 0.52)
    }
}

extension DynamicIslandNotificationStyle {
    var tint: Color {
        switch self {
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .error: .red
        case .media: Color(red: 0.36, green: 0.86, blue: 0.52)
        case .battery: .green
        case .system: .white
        }
    }
}
