import AppKit
import SwiftUI

struct ThumbnailDragInteractionView: NSViewRepresentable {
    let image: NSImage
    let stackDirection: StackDirection
    let openAction: () -> Void
    let pasteboardWriter: () -> NSPasteboardWriting?
    let dragChanged: (ScreenshotDragUpdate) -> Void
    let dragEnded: (ScreenshotDragUpdate, Bool) -> Void

    func makeNSView(context: Context) -> ThumbnailDragInteractionNSView {
        let view = ThumbnailDragInteractionNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: ThumbnailDragInteractionNSView, context: Context) {
        nsView.image = image
        nsView.stackDirection = stackDirection
        nsView.openAction = openAction
        nsView.pasteboardWriter = pasteboardWriter
        nsView.dragChanged = dragChanged
        nsView.dragEnded = dragEnded
    }
}

final class ThumbnailDragInteractionNSView: NSView, NSDraggingSource {
    /// How far the pointer must travel perpendicular to the stack before a drag
    /// is treated as "pull the screenshot out" instead of a reorder.
    private static let externalDragCrossAxisThreshold: CGFloat = 26

    var image: NSImage?
    var stackDirection: StackDirection = .vertical
    var openAction: () -> Void = {}
    var pasteboardWriter: () -> NSPasteboardWriting? = { nil }
    var dragChanged: (ScreenshotDragUpdate) -> Void = { _ in }
    var dragEnded: (ScreenshotDragUpdate, Bool) -> Void = { _, _ in }

    private var initialWindowPoint: NSPoint?
    private var initialScreenPoint: NSPoint?
    private var didStartDrag = false
    private var didBeginDraggingSession = false
    private var didFinishDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else {
            super.mouseDown(with: event)
            return
        }

        initialWindowPoint = event.locationInWindow
        initialScreenPoint = window?.convertPoint(toScreen: event.locationInWindow)
        didStartDrag = false
        didBeginDraggingSession = false
        didFinishDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialWindowPoint, !didFinishDrag else {
            return
        }

        let translation = translation(from: initialWindowPoint, toWindowPoint: event.locationInWindow)
        guard hypot(translation.width, translation.height) >= 4 else {
            return
        }

        didStartDrag = true
        dragChanged(dragUpdate(translation: translation, event: event))

        if shouldBeginExternalDrag(with: event, translation: translation) {
            beginExternalDraggingSessionIfNeeded(with: event, currentTranslation: translation)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !didFinishDrag else {
            resetDrag()
            return
        }

        guard didStartDrag else {
            resetDrag()
            openAction()
            return
        }

        finishDrag(
            at: window?.convertPoint(toScreen: event.locationInWindow),
            didCompleteExternalDrop: false
        )
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard !didFinishDrag, let initialScreenPoint else {
            return
        }

        let translation = translation(from: initialScreenPoint, toScreenPoint: screenPoint)
        dragChanged(ScreenshotDragUpdate(translation: translation, screenPoint: screenPoint))
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        if didFinishDrag {
            resetDrag()
            return
        }

        finishDrag(at: screenPoint, didCompleteExternalDrop: operation != [])
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    private func shouldBeginExternalDrag(with event: NSEvent, translation: CGSize) -> Bool {
        // Holding Option always forces a pull-out, regardless of direction.
        if event.modifierFlags.contains(.option) {
            return true
        }

        // Native-feeling pull-out: a drag that moves mostly perpendicular to the
        // stack axis (e.g. sideways on a vertical stack) lifts the item out so it
        // can be dropped into other apps, while movement along the axis reorders.
        let alongAxis: CGFloat
        let crossAxis: CGFloat
        switch stackDirection {
        case .vertical:
            alongAxis = abs(translation.height)
            crossAxis = abs(translation.width)
        case .horizontal:
            alongAxis = abs(translation.width)
            crossAxis = abs(translation.height)
        }

        if crossAxis >= Self.externalDragCrossAxisThreshold, crossAxis > alongAxis {
            return true
        }

        // Dragging the pointer clear of the shelf also pulls the item out.
        guard let contentView = window?.contentView else {
            return false
        }

        let pointInContent = contentView.convert(event.locationInWindow, from: nil)
        let reorderBounds = contentView.bounds.insetBy(dx: -12, dy: -12)
        return !reorderBounds.contains(pointInContent)
    }

    private func beginExternalDraggingSessionIfNeeded(with event: NSEvent, currentTranslation: CGSize) {
        guard !didBeginDraggingSession,
              let writer = pasteboardWriter(),
              let image,
              initialScreenPoint != nil else {
            return
        }

        didBeginDraggingSession = true
        didFinishDrag = true
        dragEnded(dragUpdate(translation: currentTranslation, event: event), true)

        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        draggingItem.setDraggingFrame(bounds, contents: image)

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    private func finishDrag(at screenPoint: NSPoint?, didCompleteExternalDrop: Bool) {
        guard !didFinishDrag else {
            return
        }

        didFinishDrag = true

        let translation: CGSize
        if let initialScreenPoint, let screenPoint {
            translation = self.translation(from: initialScreenPoint, toScreenPoint: screenPoint)
        } else {
            translation = .zero
        }

        dragEnded(ScreenshotDragUpdate(translation: translation, screenPoint: screenPoint), didCompleteExternalDrop)
        initialWindowPoint = nil
        initialScreenPoint = nil
        didStartDrag = false
        didBeginDraggingSession = false
    }

    private func dragUpdate(translation: CGSize, event: NSEvent) -> ScreenshotDragUpdate {
        ScreenshotDragUpdate(
            translation: translation,
            screenPoint: window?.convertPoint(toScreen: event.locationInWindow)
        )
    }

    private func resetDrag() {
        initialWindowPoint = nil
        initialScreenPoint = nil
        didStartDrag = false
        didBeginDraggingSession = false
        didFinishDrag = false
    }

    private func translation(from start: NSPoint, toWindowPoint end: NSPoint) -> CGSize {
        CGSize(width: end.x - start.x, height: start.y - end.y)
    }

    private func translation(from start: NSPoint, toScreenPoint end: NSPoint) -> CGSize {
        CGSize(width: end.x - start.x, height: start.y - end.y)
    }
}

struct ThumbnailScreenFrameReader: NSViewRepresentable {
    let id: UUID
    let onChange: (UUID, CGRect?) -> Void

    func makeNSView(context: Context) -> ThumbnailScreenFrameNSView {
        let view = ThumbnailScreenFrameNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: ThumbnailScreenFrameNSView, context: Context) {
        nsView.id = id
        nsView.onChange = onChange
        nsView.queueFrameUpdate()
    }
}

final class ThumbnailScreenFrameNSView: NSView {
    var id: UUID?
    var onChange: (UUID, CGRect?) -> Void = { _, _ in }

    private var lastReportedFrame: CGRect?
    private var isFrameUpdateQueued = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        queueFrameUpdate()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        queueFrameUpdate()
    }

    override func layout() {
        super.layout()
        queueFrameUpdate()
    }

    func queueFrameUpdate() {
        guard !isFrameUpdateQueued else {
            return
        }

        isFrameUpdateQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.isFrameUpdateQueued = false
            self?.reportFrame()
        }
    }

    private func reportFrame() {
        guard let id else {
            return
        }

        guard let window else {
            lastReportedFrame = nil
            onChange(id, nil)
            return
        }

        let frameInWindow = convert(bounds, to: nil)
        let screenFrame = window.convertToScreen(frameInWindow)

        guard screenFrame != lastReportedFrame else {
            return
        }

        lastReportedFrame = screenFrame
        onChange(id, screenFrame)
    }
}
