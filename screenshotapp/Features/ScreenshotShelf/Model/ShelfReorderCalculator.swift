import CoreGraphics
import Foundation

/// A single in-flight reorder drag. Pure value type shared by the view and the
/// reorder calculator.
struct ScreenshotReorderDrag: Equatable {
    let itemID: UUID
    let sourceIndex: Int
    let translation: CGFloat
    let screenPoint: CGPoint?
    let initialFrame: CGRect?
}

/// Pure geometry for translating a drag into a destination index. Extracted from
/// `ScreenshotShelfView` so the reorder rules are testable without SwiftUI.
struct ShelfReorderCalculator {
    let stackDirection: StackDirection
    /// Distance from one card's leading edge to the next (card length + spacing).
    let itemStep: CGFloat

    /// Destination index for the dragged item, computed against the *remaining*
    /// items' on-screen frames; falls back to step-based estimation when frames
    /// are unavailable.
    func destinationIndexAfterRemoval(
        drag: ScreenshotReorderDrag,
        orderedIDs: [UUID],
        frames: [UUID: CGRect]
    ) -> Int {
        let remaining = orderedIDs.filter { $0 != drag.itemID }
        guard !remaining.isEmpty else {
            return drag.sourceIndex
        }

        guard let draggedAxisPosition = draggedReorderBoundary(for: drag) else {
            return fallbackDestinationIndexAfterRemoval(for: drag, itemCount: orderedIDs.count)
        }

        let framed = remaining.compactMap { id -> (id: UUID, frame: CGRect)? in
            guard let frame = frames[id] else { return nil }
            return (id, frame)
        }

        guard framed.count == remaining.count else {
            return fallbackDestinationIndexAfterRemoval(for: drag, itemCount: orderedIDs.count)
        }

        switch stackDirection {
        case .horizontal:
            for (index, entry) in framed.enumerated() where draggedAxisPosition < entry.frame.midX {
                return index
            }
        case .vertical:
            for (index, entry) in framed.enumerated() where draggedAxisPosition > entry.frame.midY {
                return index
            }
        }

        return remaining.count
    }

    func draggedReorderBoundary(for drag: ScreenshotReorderDrag) -> CGFloat? {
        if let initialFrame = drag.initialFrame {
            switch stackDirection {
            case .horizontal:
                if drag.translation > 0 {
                    return initialFrame.maxX + drag.translation
                } else if drag.translation < 0 {
                    return initialFrame.minX + drag.translation
                }

                return initialFrame.midX
            case .vertical:
                if drag.translation > 0 {
                    return initialFrame.minY - drag.translation
                } else if drag.translation < 0 {
                    return initialFrame.maxY - drag.translation
                }

                return initialFrame.midY
            }
        }

        guard let screenPoint = drag.screenPoint else {
            return nil
        }

        switch stackDirection {
        case .horizontal:
            return screenPoint.x
        case .vertical:
            return screenPoint.y
        }
    }

    func fallbackDestinationIndexAfterRemoval(for drag: ScreenshotReorderDrag, itemCount: Int) -> Int {
        guard itemCount > 1 else {
            return drag.sourceIndex
        }

        let threshold = itemStep * 0.18
        let distance = abs(drag.translation)

        guard distance >= threshold else {
            return drag.sourceIndex
        }

        let slotCount = Int(((distance - threshold) / itemStep).rounded(.down)) + 1
        let slotDelta = drag.translation < 0 ? -slotCount : slotCount

        return min(max(drag.sourceIndex + slotDelta, 0), itemCount - 1)
    }

    func visualInsertionIndex(destinationIndex: Int, sourceIndex: Int) -> Int {
        destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
    }
}
