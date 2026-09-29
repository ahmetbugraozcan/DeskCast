import AppKit
import Testing
@testable import screenshotapp

@MainActor
struct AnnotationEditorTests {
    private func makeModel() -> AnnotationEditorViewModel {
        AnnotationEditorViewModel(image: NSImage(size: CGSize(width: 400, height: 300)), mosaic: nil)
    }

    private func drag(_ model: AnnotationEditorViewModel, from start: CGPoint, to end: CGPoint) {
        model.beginStroke(at: start)
        model.continueStroke(to: end)
        model.endStroke()
    }

    @Test func dragAddsAnnotationWithCurrentStyle() {
        let model = makeModel()
        model.tool = .rectangle
        model.color = .blue
        model.size = .large
        drag(model, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 40))

        #expect(model.annotations.count == 1)
        #expect(model.annotations[0].rect == CGRect(x: 10, y: 10, width: 50, height: 30))
        #expect(model.annotations[0].color == .blue && model.annotations[0].size == .large)
        #expect(model.draft == nil)
    }

    @Test func clickWithoutDragIsDiscarded() {
        let model = makeModel()
        drag(model, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 11))
        #expect(model.annotations.isEmpty)
        #expect(!model.canUndo)
    }

    @Test func pointsAreClampedToTheImage() {
        let model = makeModel()
        model.tool = .blur
        drag(model, from: CGPoint(x: -20, y: -20), to: CGPoint(x: 900, y: 900))
        #expect(model.annotations[0].rect == CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test func undoAndRedoWalkTheHistory() {
        let model = makeModel()
        drag(model, from: .zero, to: CGPoint(x: 50, y: 50))
        drag(model, from: .zero, to: CGPoint(x: 80, y: 20))

        model.undo()
        #expect(model.annotations.count == 1)
        model.redo()
        #expect(model.annotations.count == 2)

        model.undo()
        drag(model, from: .zero, to: CGPoint(x: 30, y: 90))
        #expect(!model.canRedo)

        model.clearAll()
        #expect(model.annotations.isEmpty)
        model.undo()
        #expect(model.annotations.count == 2)
    }

    @Test func penKeepsEveryPoint() {
        let model = makeModel()
        model.tool = .pen
        model.beginStroke(at: CGPoint(x: 1, y: 1))
        model.continueStroke(to: CGPoint(x: 5, y: 5))
        model.continueStroke(to: CGPoint(x: 9, y: 2))
        model.endStroke()
        #expect(model.annotations[0].points.count == 4)
    }

    @Test func textCommitsOnlyWhenNotEmpty() {
        let model = makeModel()
        model.tool = .text
        model.beginStroke(at: CGPoint(x: 20, y: 20))
        model.updateText("   ")
        // A second click finishes the (empty) text instead of starting another.
        model.beginStroke(at: CGPoint(x: 90, y: 90))
        #expect(model.textDraft == nil)
        #expect(model.annotations.isEmpty)

        model.beginStroke(at: CGPoint(x: 20, y: 20))
        model.updateText("Bug")
        model.color = .green
        #expect(model.finishedAnnotations().map(\.text) == ["Bug"])
        #expect(model.annotations[0].color == .green)
    }

    @Test func switchingToolFinishesText() {
        let model = makeModel()
        model.tool = .text
        model.beginStroke(at: CGPoint(x: 20, y: 20))
        model.updateText("Hi")
        model.tool = .arrow
        #expect(model.annotations.count == 1)
    }

    @Test func mosaicGridFollowsAspectRatio() {
        let grid = AnnotationPixelation.gridSize(forPixelSize: CGSize(width: 1400, height: 700))
        #expect(grid == CGSize(width: 70, height: 35))
        #expect(AnnotationPixelation.gridSize(forPixelSize: CGSize(width: 60, height: 30)) == CGSize(width: 10, height: 5))
    }

    @Test func arrowShaftStopsBeforeTip() {
        let geometry = AnnotationArrowGeometry.head(from: .zero, to: CGPoint(x: 100, y: 0), lineWidth: 5)
        #expect(geometry.shaftEnd.x < 100 && geometry.shaftEnd.x > 70)
        #expect(geometry.head.first == CGPoint(x: 100, y: 0))
    }

    @Test func rendererKeepsImageSize() throws {
        let image = NSImage(size: CGSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        var mark = Annotation(tool: .rectangle, points: [CGPoint(x: 2, y: 2), CGPoint(x: 30, y: 15)], color: .red, size: .small)
        mark.text = ""
        let rendered = try #require(AnnotationRenderer.render(image: image, mosaic: nil, annotations: [mark]))
        #expect(rendered.size == image.size)
    }
}
