import AppKit
import Combine

/// State of one annotation editor window: the marks drawn so far, the drag in
/// progress, the text being typed, and undo/redo history. Rendering and the
/// window itself live in the view and presentation layers.
@MainActor
final class AnnotationEditorViewModel: ObservableObject {
    let image: NSImage
    let mosaic: NSImage?

    @Published private(set) var annotations: [Annotation] = []
    /// Arrow/rectangle/pen/highlight/blur mark being dragged out.
    @Published private(set) var draft: Annotation?
    /// Text mark being typed; committed on Return or the next click.
    @Published private(set) var textDraft: Annotation?
    @Published var tool: AnnotationTool = .arrow {
        didSet { if tool != .text { commitText() } }
    }
    @Published var color: AnnotationColor = .red {
        didSet { textDraft?.color = color }
    }
    @Published var size: AnnotationSize = .medium {
        didSet { textDraft?.size = size }
    }

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    init(image: NSImage, mosaic: NSImage?) {
        self.image = image
        self.mosaic = mosaic
    }

    var imageSize: CGSize { image.size }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasChanges: Bool { !annotations.isEmpty || textDraft?.isMeaningful == true }

    /// Everything to draw, including the marks still being created.
    var visibleAnnotations: [Annotation] {
        annotations + [draft].compactMap { $0 }
    }

    // MARK: - Drawing

    func beginStroke(at point: CGPoint) {
        // A click while typing only finishes the text; it doesn't start a new one.
        if textDraft != nil {
            commitText()
            if tool == .text { return }
        }
        let point = clamped(point)

        if tool == .text {
            textDraft = Annotation(tool: .text, points: [point], color: color, size: size)
            return
        }

        draft = Annotation(tool: tool, points: [point, point], color: color, size: size)
    }

    func continueStroke(to point: CGPoint) {
        guard var draft else { return }
        let point = clamped(point)

        if draft.tool == .pen {
            draft.points.append(point)
        } else {
            draft.points[draft.points.count - 1] = point
        }
        self.draft = draft
    }

    func endStroke() {
        guard let draft else { return }
        self.draft = nil
        guard draft.isMeaningful else { return }
        apply(annotations + [draft])
    }

    func updateText(_ text: String) {
        textDraft?.text = text
    }

    func commitText() {
        guard let textDraft else { return }
        self.textDraft = nil
        guard textDraft.isMeaningful else { return }
        apply(annotations + [textDraft])
    }

    func cancelText() {
        textDraft = nil
    }

    // MARK: - History

    func undo() {
        cancelText()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    func redo() {
        cancelText()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    func clearAll() {
        cancelText()
        guard !annotations.isEmpty else { return }
        apply([])
    }

    /// The final marks, with any text still being typed included.
    func finishedAnnotations() -> [Annotation] {
        commitText()
        return annotations
    }

    private func apply(_ newAnnotations: [Annotation]) {
        undoStack.append(annotations)
        redoStack.removeAll()
        annotations = newAnnotations
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), imageSize.width),
            y: min(max(point.y, 0), imageSize.height)
        )
    }
}
