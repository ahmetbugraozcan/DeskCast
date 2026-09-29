import AppKit
import SwiftUI

/// Draws the image and its annotations at `scale` (view points per image
/// point). The editor shows it fitted to the window; export renders it at
/// scale 1 through `AnnotationRenderer`, so both paths share one drawing.
struct AnnotationCanvas: View {
    let image: NSImage
    let mosaic: NSImage?
    let annotations: [Annotation]
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let fullRect = CGRect(origin: .zero, size: size)
            context.draw(Image(nsImage: image).interpolation(.high), in: fullRect)
            for annotation in annotations {
                draw(annotation, in: &context, fullRect: fullRect)
            }
        }
        .frame(width: image.size.width * scale, height: image.size.height * scale)
    }

    private func draw(_ annotation: Annotation, in context: inout GraphicsContext, fullRect: CGRect) {
        let color = Color(annotation.color)
        let lineWidth = annotation.size.lineWidth * scale
        let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let rect = scaled(annotation.rect)

        switch annotation.tool {
        case .arrow:
            let start = scaled(annotation.start)
            let end = scaled(annotation.end)
            let arrow = AnnotationArrowGeometry.head(from: start, to: end, lineWidth: lineWidth)
            var shaft = Path()
            shaft.move(to: start)
            shaft.addLine(to: arrow.shaftEnd)
            var head = Path()
            head.addLines(arrow.head)
            head.closeSubpath()
            withShadow(&context) { layer in
                layer.stroke(shaft, with: .color(color), style: stroke)
                layer.fill(head, with: .color(color))
                layer.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: lineWidth / 2, lineJoin: .round))
            }

        case .rectangle:
            withShadow(&context) { layer in
                layer.stroke(Path(roundedRect: rect, cornerRadius: lineWidth), with: .color(color), style: stroke)
            }

        case .pen:
            var path = Path()
            path.addLines(annotation.points.map(scaled))
            withShadow(&context) { layer in
                layer.stroke(path, with: .color(color), style: stroke)
            }

        case .highlight:
            context.drawLayer { layer in
                layer.blendMode = .multiply
                layer.fill(Path(rect), with: .color(color.opacity(0.45)))
            }

        case .blur:
            context.drawLayer { layer in
                layer.clip(to: Path(rect))
                if let mosaic {
                    layer.draw(Image(nsImage: mosaic).interpolation(.none), in: fullRect)
                } else {
                    layer.fill(Path(rect), with: .color(.gray))
                }
            }

        case .text:
            let text = Text(annotation.text)
                .font(.system(size: annotation.size.fontSize * scale, weight: .bold))
                .foregroundStyle(color)
            withShadow(&context) { layer in
                layer.draw(text, at: scaled(annotation.start), anchor: .topLeading)
            }
        }
    }

    /// A soft shadow keeps marks readable on both light and dark content.
    private func withShadow(_ context: inout GraphicsContext, draw: (inout GraphicsContext) -> Void) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 2 * scale, x: 0, y: scale))
            draw(&layer)
        }
    }

    private func scaled(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    private func scaled(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }
}

extension Color {
    init(_ color: AnnotationColor) {
        let rgb = color.rgb
        self.init(red: rgb.x, green: rgb.y, blue: rgb.z)
    }
}

/// Flattens the annotations into a new image with the original pixel size.
enum AnnotationRenderer {
    static func render(image: NSImage, mosaic: NSImage?, annotations: [Annotation]) -> NSImage? {
        guard image.size.width > 0 else { return nil }
        let pixelWidth = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width
            ?? Int(image.size.width)

        let renderer = ImageRenderer(
            content: AnnotationCanvas(image: image, mosaic: mosaic, annotations: annotations, scale: 1)
        )
        renderer.scale = CGFloat(pixelWidth) / image.size.width
        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: image.size)
    }
}
