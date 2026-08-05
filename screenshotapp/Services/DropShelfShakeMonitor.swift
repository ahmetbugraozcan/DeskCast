import AppKit
import Foundation

@MainActor
final class DropShelfShakeMonitor {
    var onShake: () -> Void = {}

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastPoint: CGPoint?
    private var lastDirection: CGFloat = 0
    private var directionChanges: [TimeInterval] = []
    private var lastTriggerTimestamp: TimeInterval = 0
    private var sensitivity = DropShelfSettings.defaultShakeSensitivity
    private var dragPasteboardBaselineChangeCount = 0

    func update(settings: DropShelfSettingsSnapshot) {
        sensitivity = settings.shakeSensitivity

        guard settings.openOnShake,
              PrivacyPermissionService.status(for: .accessibility).isGranted else {
            stop()
            resetGesture()
            return
        }

        startIfNeeded()
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func startIfNeeded() {
        let matching: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]

        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: matching) { [weak self] event in
                Task { @MainActor in
                    self?.handle(event)
                }
            }
        }

        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: matching) { [weak self] event in
                Task { @MainActor in
                    self?.handle(event)
                }

                return event
            }
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // Snapshot the drag pasteboard state before any drag session starts.
            dragPasteboardBaselineChangeCount = NSPasteboard(name: .drag).changeCount
            resetGesture()
            return
        case .leftMouseUp:
            resetGesture()
            return
        default:
            break
        }

        // Only shake-to-open when the user is actually dragging file/image content,
        // not for arbitrary click-drags anywhere on the screen.
        guard isContentDragActive() else {
            return
        }

        handleDrag(event)
    }

    private func isContentDragActive() -> Bool {
        let dragPasteboard = NSPasteboard(name: .drag)

        // A real drag session bumps the drag pasteboard's change count past the
        // value captured at mouse-down; a plain mouse drag leaves it unchanged.
        guard dragPasteboard.changeCount != dragPasteboardBaselineChangeCount else {
            return false
        }

        guard let types = dragPasteboard.types else {
            return false
        }

        let contentTypes: Set<NSPasteboard.PasteboardType> = [
            .fileURL,
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
        ]

        return types.contains { contentTypes.contains($0) }
    }

    private func handleDrag(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        defer {
            lastPoint = point
        }

        guard let lastPoint else {
            return
        }

        let deltaX = point.x - lastPoint.x
        let minimumDelta = max(7, 20 - CGFloat(sensitivity))

        guard abs(deltaX) >= minimumDelta else {
            return
        }

        let direction: CGFloat = deltaX > 0 ? 1 : -1
        let timestamp = event.timestamp

        if lastDirection != 0, direction != lastDirection {
            directionChanges.append(timestamp)
            directionChanges = directionChanges.filter { timestamp - $0 <= 0.8 }

            if directionChanges.count >= requiredDirectionChanges,
               timestamp - lastTriggerTimestamp > 1.2 {
                lastTriggerTimestamp = timestamp
                resetGesture()
                onShake()
                return
            }
        }

        lastDirection = direction
    }

    private var requiredDirectionChanges: Int {
        let normalized = DropShelfSettings.clampedShakeSensitivity(sensitivity)
        return max(2, 7 - Int((Double(normalized) / 2.0).rounded(.down)))
    }

    private func resetGesture() {
        lastPoint = nil
        lastDirection = 0
        directionChanges.removeAll()
    }
}
