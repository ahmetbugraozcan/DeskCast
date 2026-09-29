import AVKit
import SwiftUI

struct VideoEditorView: View {
    @ObservedObject var model: VideoEditorViewModel
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayerSurface(player: model.player)
                .background(Color.black)
                .overlay { busyOverlay }

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: model.togglePlayback) {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])
                    .help(AppLocalization.string(model.isPlaying ? "videoEdit.pause" : "videoEdit.play"))

                    VideoTrimBar(model: model)
                        .frame(height: 52)
                }

                HStack(spacing: 10) {
                    Text(verbatim: timeSummary)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Picker(AppLocalization.string("videoEdit.gif.size"), selection: $model.gifPreset) {
                        ForEach(GIFExportPreset.allCases) { preset in
                            Text(AppLocalization.string(preset.titleKey)).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()

                    Button(AppLocalization.string("Cancel"), action: cancel)
                    Button(AppLocalization.string("videoEdit.gif.export"), action: model.exportGIF)
                        .disabled(!model.canExportGIF)
                    Button(AppLocalization.string("videoEdit.trim.save"), action: model.saveTrimmedVideo)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canTrim)
                        .help(AppLocalization.string("videoEdit.trim.help"))
                }
            }
            .padding(14)
            .background(.bar)
        }
    }

    private var timeSummary: String {
        let range = model.range
        return "\(VideoTrimRange.timeText(range.start)) – \(VideoTrimRange.timeText(range.end))  ·  "
            + VideoTrimRange.timeText(range.length)
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if let operation = model.operation {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.large)
                Text(AppLocalization.string(operation == .trimming ? "videoEdit.trim.busy" : "videoEdit.gif.busy"))
                    .font(.headline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Filmstrip with draggable start/end handles; the dimmed parts are cut.
/// Clicking inside the kept part moves the playhead.
private struct VideoTrimBar: View {
    @ObservedObject var model: VideoEditorViewModel

    private static let handleWidth: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - Self.handleWidth * 2, 1)
            let duration = max(model.range.duration, 0.001)
            let startX = Self.handleWidth + width * model.range.start / duration
            let endX = Self.handleWidth + width * model.range.end / duration
            let playheadX = Self.handleWidth + width * model.playhead / duration

            ZStack(alignment: .topLeading) {
                filmstrip
                    .frame(width: width, height: proxy.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .offset(x: Self.handleWidth)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { value in
                            model.seek(to: (value.location.x / width) * duration)
                        }
                    )

                // Dim the parts that will be cut.
                Color.black.opacity(0.55)
                    .frame(width: max(startX - Self.handleWidth, 0), height: proxy.size.height)
                    .offset(x: Self.handleWidth)
                    .allowsHitTesting(false)
                Color.black.opacity(0.55)
                    .frame(width: max(Self.handleWidth + width - endX, 0), height: proxy.size.height)
                    .offset(x: endX)
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.yellow, lineWidth: 3)
                    .frame(width: max(endX - startX, 0), height: proxy.size.height)
                    .offset(x: startX)
                    .allowsHitTesting(false)

                Capsule()
                    .fill(Color.white)
                    .frame(width: 2, height: proxy.size.height + 6)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .offset(x: playheadX - 1, y: -3)
                    .allowsHitTesting(false)

                handle(systemName: "chevron.compact.left", height: proxy.size.height)
                    .offset(x: startX - Self.handleWidth)
                    .gesture(DragGesture(coordinateSpace: .named("trimBar")).onChanged { value in
                        model.setStart((value.location.x - Self.handleWidth / 2) / width * duration)
                    })
                handle(systemName: "chevron.compact.right", height: proxy.size.height)
                    .offset(x: endX)
                    .gesture(DragGesture(coordinateSpace: .named("trimBar")).onChanged { value in
                        model.setEnd((value.location.x - Self.handleWidth * 1.5) / width * duration)
                    })
            }
            .coordinateSpace(name: "trimBar")
        }
        .disabled(model.isBusy)
    }

    private var filmstrip: some View {
        HStack(spacing: 0) {
            if model.filmstrip.isEmpty {
                Rectangle().fill(.quaternary)
            } else {
                ForEach(model.filmstrip.indices, id: \.self) { index in
                    Image(nsImage: model.filmstrip[index])
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
        }
    }

    private func handle(systemName: String, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.yellow)
            .frame(width: Self.handleWidth, height: height)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.7))
            )
            .contentShape(Rectangle().inset(by: -6))
            .pointerStyle(.frameResize(position: .leading))
    }
}

private struct VideoPlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
