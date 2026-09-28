import AppKit
import SwiftUI

/// Notch-anchored "Dynamic Island". The panel is a fixed, transparent canvas; the
/// island shape inside it morphs between modes with a spring so AppKit never has
/// to animate the window frame. `DynamicIslandPanelCoordinator` sizes the panel
/// and its hover region from the static metrics below.
struct DynamicIslandView: View {
    @ObservedObject var store: DynamicIslandViewModel
    @Namespace private var namespace

    static let shadowPadding: CGFloat = 26
    static let expandedMinimumWidth: CGFloat = 440
    static let expandedMediaContentHeight: CGFloat = 150
    static let expandedIdleContentHeight: CGFloat = 70
    static let notificationContentHeight: CGFloat = 60
    static let notificationMinimumWidth: CGFloat = 380

    static let morphAnimation = Animation.spring(response: 0.42, dampingFraction: 0.76)

    // MARK: - Metrics

    static func panelSize(for geometry: DynamicIslandGeometry) -> CGSize {
        let islandWidth = max(expandedMinimumWidth, geometry.notchSize.width + 220) + cornerMetrics(for: .expanded).top * 2

        return CGSize(
            width: islandWidth + shadowPadding * 2,
            height: geometry.notchSize.height + expandedMediaContentHeight + shadowPadding
        )
    }

    /// Full island frame for a mode, including the flared top "ears".
    static func islandSize(
        for mode: DynamicIslandMode,
        geometry: DynamicIslandGeometry,
        hasMedia: Bool
    ) -> CGSize {
        let notch = geometry.notchSize
        let ears = cornerMetrics(for: mode).top * 2

        switch mode {
        case .idle:
            return CGSize(width: notch.width + ears, height: notch.height)
        case .compactMedia:
            let sideWidth = notch.height + 18
            let centerWidth = geometry.hasNotch ? notch.width : max(notch.width, 220)
            return CGSize(width: centerWidth + sideWidth * 2 + ears, height: notch.height)
        case .notification:
            return CGSize(
                width: max(notificationMinimumWidth, notch.width + 160) + ears,
                height: notch.height + notificationContentHeight
            )
        case .expanded:
            return CGSize(
                width: max(expandedMinimumWidth, notch.width + 220) + ears,
                height: notch.height + (hasMedia ? expandedMediaContentHeight : expandedIdleContentHeight)
            )
        }
    }

    static func cornerMetrics(for mode: DynamicIslandMode) -> (top: CGFloat, bottom: CGFloat) {
        switch mode {
        case .idle: return (top: 6, bottom: 9)
        case .compactMedia: return (top: 6, bottom: 13)
        case .notification: return (top: 12, bottom: 24)
        case .expanded: return (top: 14, bottom: 30)
        }
    }

    // MARK: - Body

    var body: some View {
        let mode = store.mode
        let geometry = store.geometry
        let size = Self.islandSize(for: mode, geometry: geometry, hasMedia: store.hasMedia)
        let corners = Self.cornerMetrics(for: mode)
        let shape = DynamicIslandShape(topCornerRadius: corners.top, bottomCornerRadius: corners.bottom)
        // On displays without a notch the idle island disappears; the hover
        // region at the top center still reveals it.
        let isShapeVisible = mode != .idle || geometry.hasNotch

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                content(for: mode, geometry: geometry)
                    .padding(.horizontal, corners.top)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .clipShape(shape)
            .contentShape(shape)
            .shadow(color: .black.opacity(mode == .idle ? 0 : 0.38), radius: mode == .expanded ? 18 : 10, y: 6)
            .opacity(isShapeVisible ? 1 : 0)
            .onTapGesture {
                store.handleTap()
            }

            Spacer(minLength: 0)
        }
        .frame(
            width: Self.panelSize(for: geometry).width,
            height: Self.panelSize(for: geometry).height,
            alignment: .top
        )
        .animation(Self.morphAnimation, value: mode)
        .animation(Self.morphAnimation, value: size)
        .environment(\.colorScheme, .dark)
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
                    geometry: geometry,
                    namespace: namespace
                )
                .transition(Self.contentTransition)
            }
        case .notification:
            if let notification = store.activeNotification {
                NotificationBannerView(notification: notification, geometry: geometry)
                    .id(notification.id)
                    .transition(Self.contentTransition)
            }
        case .expanded:
            Group {
                if store.hasMedia, let nowPlaying = store.nowPlaying {
                    ExpandedMediaView(
                        nowPlaying: nowPlaying,
                        geometry: geometry,
                        namespace: namespace,
                        onPrevious: { store.previousTrack() },
                        onPlayPause: { store.togglePlayPause() },
                        onNext: { store.nextTrack() },
                        onOpenPlayer: { store.openPlayer() }
                    )
                } else {
                    ExpandedIdleView(
                        geometry: geometry,
                        showsPlayers: store.preferences.showsNowPlaying,
                        onOpenPlayer: { store.openPlayer($0) }
                    )
                }
            }
            .transition(Self.contentTransition)
        }
    }

    private static var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.86, anchor: .top))
                .animation(morphAnimation.delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
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

private struct CompactMediaView: View {
    let nowPlaying: NowPlayingInfo
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

            EqualizerBarsView(isPlaying: nowPlaying.isPlaying, tint: nowPlaying.tintColor)
                .frame(width: 18, height: 13)
                .matchedGeometryEffect(id: "equalizer", in: namespace)
        }
        .padding(.horizontal, 10)
        .frame(height: height)
    }
}

// MARK: - Expanded

private struct ExpandedMediaView: View {
    let nowPlaying: NowPlayingInfo
    let geometry: DynamicIslandGeometry
    let namespace: Namespace.ID
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onOpenPlayer: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onOpenPlayer) {
                    ArtworkView(nowPlaying: nowPlaying, cornerRadius: 12)
                        .frame(width: 58, height: 58)
                        .matchedGeometryEffect(id: "artwork", in: namespace)
                        .shadow(color: nowPlaying.tintColor.opacity(0.35), radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .help(AppLocalization.formatted("Open %@", nowPlaying.player.displayName))

                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(nowPlaying.artist.isEmpty ? nowPlaying.album : nowPlaying.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)

                    Text(nowPlaying.player.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)

                EqualizerBarsView(isPlaying: nowPlaying.isPlaying, tint: nowPlaying.tintColor)
                    .frame(width: 22, height: 18)
                    .matchedGeometryEffect(id: "equalizer", in: namespace)
            }

            PlaybackProgressView(nowPlaying: nowPlaying)

            HStack(spacing: 34) {
                MediaControlButton(systemImage: "backward.fill", size: 17, action: onPrevious)
                    .help(AppLocalization.string("Previous Track"))

                MediaControlButton(
                    systemImage: nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                    size: 24,
                    action: onPlayPause
                )
                .help(AppLocalization.string("Play / Pause"))

                MediaControlButton(systemImage: "forward.fill", size: 17, action: onNext)
                    .help(AppLocalization.string("Next Track"))
            }
        }
        .padding(.top, geometry.notchSize.height + 4)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }
}

private struct ExpandedIdleView: View {
    let geometry: DynamicIslandGeometry
    let showsPlayers: Bool
    let onOpenPlayer: (MediaPlayerApp) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .environment(\.locale, AppLocalization.currentLocale)
            }

            Spacer(minLength: 12)

            if showsPlayers {
                VStack(alignment: .trailing, spacing: 7) {
                    Label(AppLocalization.string("Nothing playing"), systemImage: "music.note")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    HStack(spacing: 8) {
                        ForEach(MediaPlayerApp.allCases) { player in
                            if let icon = player.appIcon {
                                Button {
                                    onOpenPlayer(player)
                                } label: {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(IslandPressButtonStyle())
                                .help(AppLocalization.formatted("Open %@", player.displayName))
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, geometry.notchSize.height + 2)
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }
}

private struct PlaybackProgressView: View {
    let nowPlaying: NowPlayingInfo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = nowPlaying.elapsed(at: context.date)
            let progress = nowPlaying.progress(at: context.date)

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
                            .animation(.linear(duration: 1), value: progress)
                    }
                }
                .frame(height: 4)

                Text(nowPlaying.duration > 0 ? "-" + Self.format(nowPlaying.duration - elapsed) : "--:--")
                    .frame(width: 42, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
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

private struct NotificationBannerView: View {
    let notification: DynamicIslandNotification
    let geometry: DynamicIslandGeometry

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

            if let progress = notification.progress {
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
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
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

private struct ProgressRingView: View {
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

private struct ArtworkView: View {
    let nowPlaying: NowPlayingInfo
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: nowPlaying.artwork != nil)
    }
}

/// Four capsules bouncing on offset sine waves while playing; they settle into
/// short dots when paused.
private struct EqualizerBarsView: View {
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

private struct MediaControlButton: View {
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

private struct IslandPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IslandPressButtonBody(configuration: configuration)
    }
}

/// Separate view so the hover highlight can keep its own `@State`.
private struct IslandPressButtonBody: View {
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

private extension NowPlayingInfo {
    var tintColor: Color {
        artworkTint.map(Color.init(nsColor:)) ?? Color(red: 0.36, green: 0.86, blue: 0.52)
    }
}

private extension DynamicIslandNotificationStyle {
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
