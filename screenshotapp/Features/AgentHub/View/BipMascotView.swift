import AppKit
import SwiftUI

/// Bip, drawn in code: a little monitor on a stand, LED eyes on its screen
/// that follow the pointer, and an antenna lamp in the mood's color.
/// Hover makes its eyes grow; a click squishes it (and annoys it); three
/// quick clicks make it dizzy.
struct BipMascotView: View {
    let mood: BipMood
    var size: CGFloat = 56
    /// Replaces the mood's color (an integration's own Bip).
    var tint: BipRGB?
    /// Clicks are handled here unless the caller wants them.
    var isInteractive = true
    var onPoke: (() -> Void)?

    @State private var moodChangedAt = Date()
    @State private var pokedAt: Date?
    @State private var pokes: [Date] = []
    @State private var dizzyUntil: Date?
    @State private var isHovered = false

    private static let dizzyDuration: TimeInterval = 3.2
    private static let annoyedDuration: TimeInterval = 0.9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            Canvas { canvas, canvasSize in
                var renderer = BipRenderer(
                    mood: displayedMood(at: context.date),
                    rgb: tint ?? displayedMood(at: context.date).tint,
                    time: context.date.timeIntervalSinceReferenceDate,
                    sinceMoodChange: context.date.timeIntervalSince(moodChangedAt),
                    sincePoke: pokedAt.map { context.date.timeIntervalSince($0) },
                    isHovered: isHovered,
                    gaze: Self.gaze()
                )
                renderer.draw(in: &canvas, size: canvasSize)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            guard isInteractive else { return }
            poke()
        }
        .onChange(of: mood) { _, _ in
            moodChangedAt = Date()
        }
        .accessibilityHidden(true)
    }

    private func displayedMood(at date: Date) -> BipMood {
        if let dizzyUntil, date < dizzyUntil { return .dizzy }
        if let pokedAt, date.timeIntervalSince(pokedAt) < Self.annoyedDuration { return .annoyed }
        return mood
    }

    private func poke() {
        let now = Date()
        pokedAt = now
        pokes = pokes.filter { now.timeIntervalSince($0) < 1.7 } + [now]
        if pokes.count >= 3 {
            pokes = []
            dizzyUntil = now.addingTimeInterval(Self.dizzyDuration)
            BipSoundPlayer.shared.play(.dizzy)
        } else {
            BipSoundPlayer.shared.play(.poke)
        }
        onPoke?()
    }

    /// Where the pointer is, relative to the top middle of its screen (where
    /// the island sits), squashed to -1...1.
    private static func gaze() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            return .zero
        }
        let dx = mouse.x - screen.frame.midX
        let dy = (screen.frame.maxY - 60) - mouse.y
        return CGPoint(x: tanh(dx / 320), y: tanh(dy / 260))
    }
}

/// The drawing itself, in a square canvas.
private struct BipRenderer {
    let mood: BipMood
    let rgb: BipRGB
    let time: TimeInterval
    let sinceMoodChange: TimeInterval
    let sincePoke: TimeInterval?
    let isHovered: Bool
    let gaze: CGPoint

    private var side: CGFloat = 0
    private var tint = Color.white

    init(
        mood: BipMood, rgb: BipRGB, time: TimeInterval, sinceMoodChange: TimeInterval,
        sincePoke: TimeInterval?, isHovered: Bool, gaze: CGPoint
    ) {
        self.mood = mood
        self.rgb = rgb
        self.time = time
        self.sinceMoodChange = sinceMoodChange
        self.sincePoke = sincePoke
        self.isHovered = isHovered
        self.gaze = gaze
        tint = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    mutating func draw(in context: inout GraphicsContext, size: CGSize) {
        side = min(size.width, size.height)
        var context = context
        context.translateBy(x: size.width / 2, y: size.height / 2)

        drawGlow(in: context)

        let motion = bodyMotion()
        context.translateBy(x: motion.offset.width, y: motion.offset.height)
        context.rotate(by: .radians(motion.rotation))
        context.scaleBy(x: motion.scale.width, y: motion.scale.height)

        drawStand(in: context)
        drawAntenna(in: context)
        drawHead(in: context)
        drawFace(in: context)
        drawExtras(in: context)
    }

    // MARK: - Motion

    private struct Motion {
        var offset: CGSize
        var rotation: Double
        var scale: CGSize
    }

    private func bodyMotion() -> Motion {
        var offset = CGSize(width: 0, height: sin(time * 2 * .pi / 3.4) * side * 0.012)
        var rotation = 0.0
        var scale = CGSize(width: 1, height: 1)

        switch mood {
        case .finished where sinceMoodChange < 1.2, .happy where sinceMoodChange < 1.2:
            offset.height -= abs(sin(sinceMoodChange * .pi * 2.5)) * side * 0.09 * (1 - sinceMoodChange / 1.2)
        case .approval:
            offset.height -= abs(sin(time * .pi * 2.2)) * side * 0.035
        case .error where sinceMoodChange < 0.6:
            offset.width = sin(sinceMoodChange * 60) * side * 0.03 * (1 - sinceMoodChange / 0.6)
        case .question:
            rotation = -0.14
        case .dizzy:
            rotation = sin(time * 7) * 0.16
        case .sleeping:
            scale.height = 1 + sin(time * 2 * .pi / 4) * 0.02
        default:
            break
        }

        if let sincePoke, sincePoke < 0.4 {
            let squish = sin(sincePoke / 0.4 * .pi) * (1 - sincePoke / 0.4)
            scale = CGSize(width: scale.width * (1 + squish * 0.14), height: scale.height * (1 - squish * 0.12))
        }

        return Motion(offset: offset, rotation: rotation, scale: scale)
    }

    // MARK: - Parts

    private func drawGlow(in context: GraphicsContext) {
        let strength: Double = switch mood {
        case .idle, .sleeping: 0.18
        case .approval, .error, .question: 0.5
        default: 0.34
        }
        let radius = side * 0.46
        context.fill(
            Path(ellipseIn: CGRect(x: -radius, y: -radius * 0.9, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [tint.opacity(strength), tint.opacity(0)]),
                center: CGPoint(x: 0, y: side * 0.02),
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    private var headRect: CGRect {
        CGRect(x: -side * 0.31, y: -side * 0.2, width: side * 0.62, height: side * 0.46)
    }

    private var screenRect: CGRect {
        headRect.insetBy(dx: side * 0.055, dy: side * 0.05)
    }

    private func drawStand(in context: GraphicsContext) {
        let neck = CGRect(x: -side * 0.045, y: headRect.maxY - side * 0.01, width: side * 0.09, height: side * 0.07)
        let base = CGRect(x: -side * 0.15, y: neck.maxY - side * 0.005, width: side * 0.3, height: side * 0.045)
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Color(white: 0.78), Color(white: 0.6)]),
            startPoint: CGPoint(x: 0, y: neck.minY),
            endPoint: CGPoint(x: 0, y: base.maxY)
        )
        context.fill(Path(roundedRect: neck, cornerRadius: side * 0.015), with: shading)
        context.fill(Path(roundedRect: base, cornerRadius: side * 0.022), with: shading)
    }

    private func drawAntenna(in context: GraphicsContext) {
        let top = CGPoint(x: side * 0.08, y: headRect.minY - side * 0.13)
        var stem = Path()
        stem.move(to: CGPoint(x: side * 0.03, y: headRect.minY + side * 0.01))
        stem.addQuadCurve(to: top, control: CGPoint(x: side * 0.02, y: headRect.minY - side * 0.07))
        context.stroke(stem, with: .color(Color(white: 0.72)), style: StrokeStyle(lineWidth: side * 0.022, lineCap: .round))

        var lamp = 1.0
        if mood.lampBlinkRate > 0 {
            lamp = 0.45 + 0.55 * (0.5 + 0.5 * sin(time * 2 * .pi * mood.lampBlinkRate / 2))
        } else if mood == .sleeping {
            lamp = 0.35
        }

        let radius = side * 0.045
        let lampRect = CGRect(x: top.x - radius, y: top.y - radius, width: radius * 2, height: radius * 2)
        var glow = context
        glow.addFilter(.blur(radius: side * 0.035))
        glow.fill(Path(ellipseIn: lampRect.insetBy(dx: -radius * 0.6, dy: -radius * 0.6)), with: .color(tint.opacity(0.7 * lamp)))
        context.fill(Path(ellipseIn: lampRect), with: .color(tint.opacity(0.35 + 0.65 * lamp)))
        context.fill(
            Path(ellipseIn: lampRect.insetBy(dx: radius * 0.45, dy: radius * 0.45).offsetBy(dx: -radius * 0.25, dy: -radius * 0.25)),
            with: .color(.white.opacity(0.8))
        )

        if mood == .approval {
            drawText("!", at: CGPoint(x: top.x + side * 0.1, y: top.y - side * 0.02), size: side * 0.16, in: context)
        }
    }

    private func drawHead(in context: GraphicsContext) {
        let head = Path(roundedRect: headRect, cornerRadius: side * 0.12, style: .continuous)
        context.fill(head, with: .linearGradient(
            Gradient(colors: [Color(red: 0.95, green: 0.96, blue: 0.98), Color(red: 0.76, green: 0.8, blue: 0.86)]),
            startPoint: CGPoint(x: headRect.minX, y: headRect.minY),
            endPoint: CGPoint(x: headRect.maxX, y: headRect.maxY)
        ))
        context.stroke(head, with: .color(.white.opacity(0.6)), lineWidth: side * 0.008)

        let screen = Path(roundedRect: screenRect, cornerRadius: side * 0.075, style: .continuous)
        context.fill(screen, with: .color(Color(red: 0.06, green: 0.075, blue: 0.1)))
        context.fill(screen, with: .radialGradient(
            Gradient(colors: [tint.opacity(mood == .sleeping ? 0.08 : 0.24), tint.opacity(0)]),
            center: CGPoint(x: screenRect.midX, y: screenRect.maxY),
            startRadius: 0,
            endRadius: screenRect.width * 0.8
        ))
        // Glass reflection.
        var shine = Path()
        shine.move(to: CGPoint(x: screenRect.minX + side * 0.04, y: screenRect.minY + side * 0.02))
        shine.addLine(to: CGPoint(x: screenRect.minX + side * 0.12, y: screenRect.minY + side * 0.02))
        context.stroke(shine, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: side * 0.014, lineCap: .round))
    }

    // MARK: - Face

    private var eyeColor: Color {
        return Color(red: 0.55 + rgb.red * 0.45, green: 0.55 + rgb.green * 0.45, blue: 0.55 + rgb.blue * 0.45)
    }

    private var eyeCenters: (CGPoint, CGPoint) {
        var look = gaze
        switch mood {
        case .thinking: look = CGPoint(x: 0.7, y: -0.8)
        case .searching: look = CGPoint(x: sin(time * 3), y: 0)
        case .sleeping, .dizzy: look = .zero
        default: break
        }
        let center = CGPoint(
            x: screenRect.midX + look.x * side * 0.05,
            y: screenRect.midY - side * 0.025 + look.y * side * 0.035
        )
        let spread = side * 0.1
        return (CGPoint(x: center.x - spread, y: center.y), CGPoint(x: center.x + spread, y: center.y))
    }

    /// 0 = open, 1 = shut; a blink every few seconds, sometimes twice.
    private var blink: Double {
        let period = 4.1
        let phase = time.truncatingRemainder(dividingBy: period)
        let isDouble = Int(time / period) % 4 == 1
        for start in isDouble ? [0.0, 0.26] : [0.0] where phase >= start && phase < start + 0.16 {
            return sin((phase - start) / 0.16 * .pi)
        }
        return 0
    }

    private func drawFace(in context: GraphicsContext) {
        let (left, right) = eyeCenters
        let grow: CGFloat = isHovered ? 1.12 : 1
        let eye = side * 0.06 * grow
        let color = eyeColor

        var glow = context
        glow.addFilter(.blur(radius: side * 0.02))

        for (index, point) in [left, right].enumerated() {
            for layer in [glow, context] {
                drawEye(at: point, size: eye, isLeft: index == 0, color: color, in: layer)
            }
        }

        drawMouth(below: CGPoint(x: (left.x + right.x) / 2, y: left.y + side * 0.085), color: color, in: context)
    }

    private func drawEye(at point: CGPoint, size eye: CGFloat, isLeft: Bool, color: Color, in context: GraphicsContext) {
        let line = StrokeStyle(lineWidth: side * 0.022, lineCap: .round, lineJoin: .round)

        switch mood {
        case .finished, .happy:
            var arc = Path()
            arc.move(to: CGPoint(x: point.x - eye * 0.7, y: point.y + eye * 0.3))
            arc.addQuadCurve(
                to: CGPoint(x: point.x + eye * 0.7, y: point.y + eye * 0.3),
                control: CGPoint(x: point.x, y: point.y - eye * 0.9)
            )
            context.stroke(arc, with: .color(color), style: line)
        case .error:
            var cross = Path()
            cross.move(to: CGPoint(x: point.x - eye * 0.55, y: point.y - eye * 0.55))
            cross.addLine(to: CGPoint(x: point.x + eye * 0.55, y: point.y + eye * 0.55))
            cross.move(to: CGPoint(x: point.x + eye * 0.55, y: point.y - eye * 0.55))
            cross.addLine(to: CGPoint(x: point.x - eye * 0.55, y: point.y + eye * 0.55))
            context.stroke(cross, with: .color(color), style: line)
        case .sleeping:
            var closed = Path()
            closed.move(to: CGPoint(x: point.x - eye * 0.6, y: point.y))
            closed.addQuadCurve(to: CGPoint(x: point.x + eye * 0.6, y: point.y), control: CGPoint(x: point.x, y: point.y + eye * 0.45))
            context.stroke(closed, with: .color(color.opacity(0.7)), style: line)
        case .rateLimited:
            let rect = CGRect(x: point.x - eye * 0.5, y: point.y, width: eye, height: eye * 0.55)
            context.fill(Path(roundedRect: rect, cornerRadius: eye * 0.25), with: .color(color))
        case .annoyed:
            var slant = Path()
            let tilt = isLeft ? eye * 0.35 : -eye * 0.35
            slant.move(to: CGPoint(x: point.x - eye * 0.6, y: point.y - tilt))
            slant.addLine(to: CGPoint(x: point.x + eye * 0.6, y: point.y + tilt))
            context.stroke(slant, with: .color(color), style: line)
        case .dizzy:
            var spiral = Path()
            let turns = 2.2
            let steps = 28
            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                let angle = fraction * turns * 2 * .pi + time * 6 * (isLeft ? 1 : -1)
                let radius = eye * 0.65 * fraction
                let spot = CGPoint(x: point.x + cos(angle) * radius, y: point.y + sin(angle) * radius)
                if step == 0 { spiral.move(to: spot) } else { spiral.addLine(to: spot) }
            }
            context.stroke(spiral, with: .color(color), style: StrokeStyle(lineWidth: side * 0.015, lineCap: .round))
        case .approval:
            let radius = eye * 0.72
            context.fill(Self.circle(at: point, radius: radius), with: .color(color))
            let pupil = CGPoint(x: point.x + radius * 0.05, y: point.y - radius * 0.3)
            context.fill(Self.circle(at: pupil, radius: radius * 0.25), with: .color(.black.opacity(0.35)))
        default:
            let height = eye * 1.5 * (1 - blink * 0.88) * (mood == .question && !isLeft ? 1.18 : 1)
            let rect = CGRect(x: point.x - eye * 0.42, y: point.y - height / 2, width: eye * 0.84, height: max(height, side * 0.012))
            context.fill(Path(roundedRect: rect, cornerRadius: eye * 0.4), with: .color(color))
        }
    }

    private func drawMouth(below point: CGPoint, color: Color, in context: GraphicsContext) {
        let width = side * 0.06
        let style = StrokeStyle(lineWidth: side * 0.016, lineCap: .round)
        var mouth = Path()

        switch mood {
        case .approval, .question:
            let radius = side * 0.018
            context.stroke(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(color.opacity(0.85)), style: style)
            return
        case .error, .annoyed, .rateLimited:
            mouth.move(to: CGPoint(x: point.x - width / 2, y: point.y + side * 0.01))
            mouth.addQuadCurve(
                to: CGPoint(x: point.x + width / 2, y: point.y + side * 0.01),
                control: CGPoint(x: point.x, y: point.y - side * 0.02)
            )
        case .working, .searching, .thinking, .sleeping, .dizzy:
            mouth.move(to: CGPoint(x: point.x - width * 0.35, y: point.y))
            mouth.addLine(to: CGPoint(x: point.x + width * 0.35, y: point.y))
        case .idle, .finished, .happy:
            mouth.move(to: CGPoint(x: point.x - width / 2, y: point.y - side * 0.008))
            mouth.addQuadCurve(
                to: CGPoint(x: point.x + width / 2, y: point.y - side * 0.008),
                control: CGPoint(x: point.x, y: point.y + side * 0.03)
            )
        }
        context.stroke(mouth, with: .color(color.opacity(0.85)), style: style)
    }

    // MARK: - Extras

    private func drawExtras(in context: GraphicsContext) {
        switch mood {
        case .thinking, .working:
            // Three dots that light up in turn, like a loading screen.
            for index in 0..<3 {
                let lit = Int(time * 3) % 3 == index
                let radius = side * 0.012
                let center = CGPoint(x: screenRect.maxX - side * 0.1 + CGFloat(index) * side * 0.032, y: screenRect.maxY - side * 0.04)
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(eyeColor.opacity(lit ? 1 : 0.3)))
            }
        case .question:
            drawText("?", at: CGPoint(x: headRect.maxX + side * 0.05, y: headRect.minY - side * 0.02), size: side * 0.18, in: context)
        case .sleeping:
            for index in 0..<2 {
                let progress = (time * 0.4 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                var faded = context
                faded.opacity = 1 - progress
                let spot = CGPoint(x: headRect.maxX + side * (0.02 + progress * 0.08), y: headRect.minY - progress * side * 0.18)
                drawText("z", at: spot,
                         size: side * (0.09 + progress * 0.05), in: faded)
            }
        case .rateLimited:
            let fall = (time * 0.6).truncatingRemainder(dividingBy: 1)
            let drop = CGRect(x: headRect.maxX - side * 0.06, y: headRect.minY + side * (0.04 + fall * 0.05),
                              width: side * 0.035, height: side * 0.05)
            context.fill(Path(ellipseIn: drop), with: .color(Color(red: 0.55, green: 0.8, blue: 1).opacity(0.9)))
        case .finished, .happy:
            drawSparkles(in: context)
        default:
            break
        }
    }

    private func drawSparkles(in context: GraphicsContext) {
        guard sinceMoodChange < 1.6 else { return }
        let progress = sinceMoodChange / 1.6
        for index in 0..<5 {
            let angle = Double(index) / 5 * 2 * .pi - .pi / 2
            let distance = side * (0.3 + progress * 0.18)
            let center = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance * 0.8)
            let radius = side * 0.03 * (1 - progress)
            var star = Path()
            star.move(to: CGPoint(x: center.x, y: center.y - radius * 2))
            star.addLine(to: CGPoint(x: center.x + radius * 0.5, y: center.y))
            star.addLine(to: CGPoint(x: center.x, y: center.y + radius * 2))
            star.addLine(to: CGPoint(x: center.x - radius * 0.5, y: center.y))
            star.closeSubpath()
            context.fill(star, with: .color(Color(red: 1, green: 0.85, blue: 0.4).opacity(1 - progress)))
        }
    }

    private static func circle(at center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func drawText(_ text: String, at point: CGPoint, size: CGFloat, in context: GraphicsContext) {
        context.draw(
            Text(text).font(.system(size: size, weight: .heavy, design: .rounded)).foregroundStyle(tint),
            at: point
        )
    }
}
