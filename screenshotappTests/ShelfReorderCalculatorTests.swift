import CoreGraphics
import Foundation
import Testing
@testable import screenshotapp

struct ShelfReorderCalculatorTests {

    private func drag(source: Int, translation: CGFloat) -> ScreenshotReorderDrag {
        ScreenshotReorderDrag(
            itemID: UUID(),
            sourceIndex: source,
            translation: translation,
            screenPoint: nil,
            initialFrame: nil
        )
    }

    @Test func visualInsertionIndexShiftsWhenMovingDown() {
        let calc = ShelfReorderCalculator(stackDirection: .vertical, itemStep: 100)
        #expect(calc.visualInsertionIndex(destinationIndex: 3, sourceIndex: 1) == 4)
        #expect(calc.visualInsertionIndex(destinationIndex: 1, sourceIndex: 3) == 1)
    }

    @Test func fallbackKeepsSourceIndexBelowThreshold() {
        let calc = ShelfReorderCalculator(stackDirection: .horizontal, itemStep: 100)
        // threshold is itemStep * 0.18 = 18; a 10pt drag stays put.
        let result = calc.fallbackDestinationIndexAfterRemoval(for: drag(source: 2, translation: 10), itemCount: 5)
        #expect(result == 2)
    }

    @Test func fallbackMovesBySlotsAndClamps() {
        let calc = ShelfReorderCalculator(stackDirection: .horizontal, itemStep: 100)
        // 250pt with threshold 18 → slotCount = floor((250-18)/100)+1 = 3
        #expect(calc.fallbackDestinationIndexAfterRemoval(for: drag(source: 1, translation: 250), itemCount: 6) == 4)
        // negative direction clamps at 0
        #expect(calc.fallbackDestinationIndexAfterRemoval(for: drag(source: 1, translation: -900), itemCount: 6) == 0)
    }

    @Test func destinationUsesFramesWhenAvailable() {
        let calc = ShelfReorderCalculator(stackDirection: .vertical, itemStep: 100)
        let dragged = UUID()
        let first = UUID(), second = UUID()
        // Vertical: boundary compares against frame.midY; screenPoint drives it.
        let dragEvent = ScreenshotReorderDrag(
            itemID: dragged,
            sourceIndex: 0,
            translation: 0,
            screenPoint: CGPoint(x: 0, y: 150),
            initialFrame: nil
        )
        let frames: [UUID: CGRect] = [
            first: CGRect(x: 0, y: 100, width: 50, height: 50), // midY 125 < 150 → picks index 0
            second: CGRect(x: 0, y: 0, width: 50, height: 50)
        ]
        let result = calc.destinationIndexAfterRemoval(
            drag: dragEvent,
            orderedIDs: [dragged, first, second],
            frames: frames
        )
        #expect(result == 0)
    }
}
