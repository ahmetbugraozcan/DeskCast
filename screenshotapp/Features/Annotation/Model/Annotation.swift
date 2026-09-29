import CoreGraphics
import Foundation

enum AnnotationTool: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case pen
    case text
    case highlight
    case blur

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .pen: "scribble"
        case .text: "textformat"
        case .highlight: "highlighter"
        case .blur: "square.grid.3x3.fill"
        }
    }

    var titleKey: String { "annotate.tool.\(rawValue)" }
}

enum AnnotationColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, black, white

    var id: String { rawValue }

    /// Red, green and blue components in 0…1.
    var rgb: SIMD3<Double> {
        switch self {
        case .red: [1, 0.23, 0.19]
        case .orange: [1, 0.58, 0]
        case .yellow: [1, 0.84, 0.04]
        case .green: [0.2, 0.78, 0.35]
        case .blue: [0.04, 0.52, 1]
        case .black: [0.1, 0.1, 0.1]
        case .white: [1, 1, 1]
        }
    }
}

enum AnnotationSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var lineWidth: CGFloat {
        switch self {
        case .small: 3
        case .medium: 5
        case .large: 9
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small: 18
        case .medium: 26
        case .large: 40
        }
    }

    var symbolScale: CGFloat {
        switch self {
        case .small: 0.45
        case .medium: 0.7
        case .large: 1
        }
    }
}

/// One mark on the image. Points are in image point coordinates with a
/// top-left origin, so the same annotation renders on screen and on export.
struct Annotation: Identifiable, Equatable {
    let id = UUID()
    let tool: AnnotationTool
    var points: [CGPoint]
    var color: AnnotationColor
    var size: AnnotationSize
    var text = ""

    var start: CGPoint { points.first ?? .zero }
    var end: CGPoint { points.last ?? .zero }

    /// The rectangle spanned by the drag, for rectangle/highlight/blur.
    var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// Drags shorter than this are treated as accidental clicks and dropped.
    static let minimumExtent: CGFloat = 4

    var isMeaningful: Bool {
        switch tool {
        case .text:
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .pen:
            points.count > 1
        case .arrow:
            hypot(end.x - start.x, end.y - start.y) >= Self.minimumExtent
        case .rectangle, .highlight, .blur:
            rect.width >= Self.minimumExtent && rect.height >= Self.minimumExtent
        }
    }

    static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        lhs.id == rhs.id && lhs.points == rhs.points && lhs.text == rhs.text
            && lhs.color == rhs.color && lhs.size == rhs.size
    }
}

/// Arrow geometry: the shaft stops at the head's base so wide strokes don't
/// poke through the tip.
enum AnnotationArrowGeometry {
    static func head(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> (shaftEnd: CGPoint, head: [CGPoint]) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(lineWidth * 4, 14)
        let spread = CGFloat.pi / 7
        let left = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let right = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        let base = length * cos(spread)
        let shaftEnd = CGPoint(x: end.x - base * cos(angle), y: end.y - base * sin(angle))
        return (shaftEnd, [end, left, right])
    }
}
