import SwiftUI

// MARK: - Timer

struct TimerPanelView: View {
    @ObservedObject var timer: IslandTimerViewModel
    @ObservedObject var stopwatch: IslandStopwatchViewModel

    var body: some View {
        Group {
            switch timer.panelMode {
            case .timer: countdown
            case .stopwatch: StopwatchView(stopwatch: stopwatch)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: timer.panelMode)
    }

    private var countdown: some View {
        HStack(spacing: 22) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = timer.remaining(at: context.date)

                ZStack {
                    Circle().stroke(Color.orange.opacity(0.18), lineWidth: 8)

                    Circle()
                        .trim(from: 0, to: timer.progress(at: context.date))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: timer.progress(at: context.date))

                    Text(IslandFormat.clock(remaining))
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.isPaused ? .white.opacity(0.5) : .white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: Int(remaining.rounded(.up)))
                }
                .frame(width: 150, height: 150)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(IslandTimerViewModel.presetMinutes, id: \.self) { minutes in
                        IslandChipButton(
                            title: AppLocalization.formatted("island.timer.minutes", minutes),
                            isOn: timer.isActive && Int(timer.totalDuration) == minutes * 60
                        ) {
                            timer.start(minutes: minutes)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        timer.toggle()
                    } label: {
                        Label(
                            AppLocalization.string(timer.isRunning ? "island.timer.pause" : "island.timer.start"),
                            systemImage: timer.isRunning ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.orange))
                        .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(IslandScaleButtonStyle())

                    IslandChipButton(title: AppLocalization.string("island.timer.addMinute")) { timer.addMinute() }

                    if timer.isActive {
                        IslandChipButton(title: AppLocalization.string("island.timer.reset"), systemImage: "arrow.counterclockwise") {
                            timer.reset()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: timer.isActive)
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Header switch between the countdown and the stopwatch.
struct TimerModePicker: View {
    @ObservedObject var timer: IslandTimerViewModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(IslandTimerPanelMode.allCases) { mode in
                IslandChipButton(title: AppLocalization.string(mode.titleKey), isOn: timer.panelMode == mode) {
                    timer.panelMode = mode
                }
            }
        }
    }
}

// MARK: - Stopwatch

private struct StopwatchView: View {
    @ObservedObject var stopwatch: IslandStopwatchViewModel

    private static let tint = Color.cyan

    var body: some View {
        HStack(spacing: 22) {
            TimelineView(.periodic(from: .now, by: stopwatch.isRunning ? 0.1 : 60)) { context in
                let elapsed = stopwatch.elapsed(at: context.date)

                ZStack {
                    Circle().stroke(Self.tint.opacity(0.18), lineWidth: 8)

                    // One lap of the ring per minute.
                    Circle()
                        .trim(from: 0, to: elapsed.truncatingRemainder(dividingBy: 60) / 60)
                        .stroke(Self.tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text(IslandFormat.stopwatch(elapsed))
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(stopwatch.isPaused ? .white.opacity(0.5) : .white)
                }
                .frame(width: 150, height: 150)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        stopwatch.toggle()
                    } label: {
                        Label(
                            AppLocalization.string(stopwatch.isRunning ? "island.timer.pause" : "island.timer.start"),
                            systemImage: stopwatch.isRunning ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(Capsule().fill(Self.tint))
                        .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(IslandScaleButtonStyle())

                    if stopwatch.isRunning {
                        IslandChipButton(title: AppLocalization.string("island.stopwatch.lap"), systemImage: "flag") {
                            stopwatch.lap()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    if stopwatch.isActive {
                        IslandChipButton(title: AppLocalization.string("island.timer.reset"), systemImage: "arrow.counterclockwise") {
                            stopwatch.reset()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: stopwatch.isRunning)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: stopwatch.isActive)

                laps
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var laps: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(stopwatch.laps.enumerated().reversed().prefix(3)), id: \.offset) { index, lap in
                HStack(spacing: 12) {
                    Text(AppLocalization.formatted("island.stopwatch.lapNumber", index + 1))
                        .foregroundStyle(IslandPalette.secondaryText)
                        .frame(width: 60, alignment: .leading)
                    Text(IslandFormat.stopwatch(lap))
                        .foregroundStyle(.white)
                }
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stopwatch.laps.count)
    }
}
