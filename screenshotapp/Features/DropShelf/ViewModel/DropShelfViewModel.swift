import AppKit
import Combine
import KeyboardShortcuts

@MainActor
final class DropShelfViewModel: ObservableObject, ShelfCollecting {
    @Published private(set) var items: [DropShelfItem] = []
    @Published private(set) var isShelfVisible = false
    @Published private(set) var isDropTargeted = false
    @Published private(set) var isInternalDragInProgress = false

    private var defaultsObserver: AnyCancellable?
    private var activeObserver: AnyCancellable?
    private var toastController: ToastPanelController?
    private let shakeMonitor = DropShelfShakeMonitor()
    private lazy var panelController = DropShelfPanelController(store: self)

    init() {
        DropShelfSettings.registerDefaults()
        ToolboxSettings.registerDefaults()

        shakeMonitor.onShake = { [weak self] in
            self?.showShelf()
        }

        defaultsObserver = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.applySettingsChange()
            }
        }

        activeObserver = NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.applySettingsChange()
            }
        }

        KeyboardShortcuts.removeHandler(for: .openDropShelf)
        KeyboardShortcuts.onKeyUp(for: .openDropShelf) { [weak self] in
            Task { @MainActor in
                self?.toggleShelf()
            }
        }

        applySettingsChange()
    }

    deinit {
        KeyboardShortcuts.removeHandler(for: .openDropShelf)
    }

    func showShelf() {
        guard ToolboxSettings.isEnabled(.dropShelf) else { return }
        isShelfVisible = true
        panelController.refresh()
    }

    func hideShelf() {
        isShelfVisible = false
        isDropTargeted = false
        isInternalDragInProgress = false
        items.removeAll()
        panelController.hide()
    }

    func toggleShelf() {
        if isShelfVisible {
            hideShelf()
        } else {
            showShelf()
        }
    }

    func addItems(from pasteboard: NSPasteboard) -> Bool {
        guard ToolboxSettings.isEnabled(.dropShelf) else {
            return false
        }

        guard !isInternalDragInProgress else {
            isDropTargeted = false
            return false
        }

        let newItems = DropShelfPasteboardReader.items(from: pasteboard)
        guard !newItems.isEmpty else {
            NSSound.beep()
            return false
        }

        let settings = DropShelfSettings.snapshot()
        items.append(contentsOf: newItems)
        trimToMaxItemCount(settings.maxItemCount)
        isShelfVisible = true
        isDropTargeted = false
        panelController.refresh()
        showToast(
            newItems.count == 1
                ? AppLocalization.formatted("Added %ld item", newItems.count)
                : AppLocalization.formatted("Added %ld items", newItems.count)
        )
        return true
    }

    /// Adds a captured screenshot image to the shelf and reveals it.
    func addScreenshot(_ image: NSImage, name: String) {
        guard ToolboxSettings.isEnabled(.dropShelf) else {
            NSSound.beep()
            showToast(
                AppLocalization.string("Enable Drop Shelf first"),
                systemImage: "exclamationmark.triangle.fill"
            )
            return
        }

        let item = DropShelfItem(kind: .image, displayName: name, image: image)
        let settings = DropShelfSettings.snapshot()
        items.append(item)
        trimToMaxItemCount(settings.maxItemCount)
        isShelfVisible = true
        panelController.refresh()
        showToast(AppLocalization.formatted("Added %ld item", 1))
    }

    func setDropTargeted(_ isTargeted: Bool) {
        guard !isInternalDragInProgress else {
            isDropTargeted = false
            return
        }

        isDropTargeted = isTargeted
    }

    func beginInternalDrag() {
        isInternalDragInProgress = true
        isDropTargeted = false
    }

    func endInternalDrag() {
        isInternalDragInProgress = false
        isDropTargeted = false
    }

    func remove(_ item: DropShelfItem) {
        items.removeAll { $0.id == item.id }
        panelController.refreshIfVisible()
    }

    func clearAll() {
        guard !items.isEmpty else {
            return
        }

        items.removeAll()
        panelController.refreshIfVisible()
    }

    func preview(_ item: DropShelfItem) {
        do {
            if let url = item.url {
                NSWorkspace.shared.open(url)
                return
            }

            let url = try DropShelfExportService.previewURL(for: item)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not preview item"), systemImage: "exclamationmark.triangle.fill")
        }
    }

    func sendAll() {
        guard !items.isEmpty else {
            return
        }

        guard let directoryURL = chooseDestinationDirectory() else {
            return
        }

        do {
            let exportedURLs = try DropShelfExportService.export(items, to: directoryURL)
            showToast(
                exportedURLs.count == 1
                    ? AppLocalization.formatted("Sent %ld item", exportedURLs.count)
                    : AppLocalization.formatted("Sent %ld items", exportedURLs.count)
            )
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not send items"), systemImage: "exclamationmark.triangle.fill")
        }
    }

    func send(_ item: DropShelfItem) {
        guard let directoryURL = chooseDestinationDirectory() else {
            return
        }

        do {
            _ = try DropShelfExportService.export([item], to: directoryURL)
            showToast(AppLocalization.formatted("Sent %@", item.displayName))
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not send item"), systemImage: "exclamationmark.triangle.fill")
        }
    }

    func copy(_ item: DropShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let fileURL = item.fileURL {
            pasteboard.writeObjects([fileURL as NSURL])
            return
        }

        if let url = item.url {
            pasteboard.writeObjects([url as NSURL])
            pasteboard.setString(url.absoluteString, forType: .string)
            return
        }

        if let text = item.text {
            pasteboard.setString(text, forType: .string)
            return
        }

        if let image = item.image {
            pasteboard.writeObjects([image])
        }
    }

    func draggingPasteboardWriter(for item: DropShelfItem) -> NSPasteboardWriting? {
        do {
            let url = try DropShelfExportService.previewURL(for: item)
            return url as NSURL
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not drag item"), systemImage: "exclamationmark.triangle.fill")
            return nil
        }
    }

    func draggingPasteboardWritersForAllItems() -> [NSPasteboardWriting] {
        do {
            return try DropShelfExportService.draggingURLs(for: items).map { $0 as NSURL }
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not drag items"), systemImage: "exclamationmark.triangle.fill")
            return []
        }
    }

    func rename(_ item: DropShelfItem, to proposedName: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        if let fileURL = items[index].fileURL {
            renameFileBackedItem(at: index, fileURL: fileURL, proposedName: trimmedName)
        } else {
            items[index].displayName = trimmedName
            panelController.refreshIfVisible()
        }
    }

    func moveItem(withID draggedID: UUID, before destinationID: UUID) {
        guard draggedID != destinationID,
              let sourceIndex = items.firstIndex(where: { $0.id == draggedID }),
              let destinationIndex = items.firstIndex(where: { $0.id == destinationID }) else {
            return
        }

        let item = items.remove(at: sourceIndex)
        let adjustedDestinationIndex = sourceIndex < destinationIndex
            ? destinationIndex - 1
            : destinationIndex
        items.insert(item, at: adjustedDestinationIndex)
        panelController.refreshIfVisible()
    }

    func moveItemBackward(_ item: DropShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              index > 0 else {
            return
        }

        items.swapAt(index, index - 1)
        panelController.refreshIfVisible()
    }

    func moveItemForward(_ item: DropShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              index < items.count - 1 else {
            return
        }

        items.swapAt(index, index + 1)
        panelController.refreshIfVisible()
    }

    private func renameFileBackedItem(at index: Int, fileURL: URL, proposedName: String) {
        let destinationURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileRenameTargetName(proposedName, originalURL: fileURL))

        guard destinationURL != fileURL else {
            items[index].displayName = destinationURL.lastPathComponent
            return
        }

        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            NSSound.beep()
            showToast(AppLocalization.string("Name already exists"), systemImage: "exclamationmark.triangle.fill")
            return
        }

        do {
            try FileManager.default.moveItem(at: fileURL, to: destinationURL)
            items[index].fileURL = destinationURL
            items[index].displayName = destinationURL.lastPathComponent
            panelController.refreshIfVisible()
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not rename item"), systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func fileRenameTargetName(_ proposedName: String, originalURL: URL) -> String {
        guard !originalURL.hasDirectoryPath else {
            return proposedName
        }

        let originalExtension = originalURL.pathExtension
        guard !originalExtension.isEmpty else {
            return proposedName
        }

        let proposedExtension = URL(fileURLWithPath: proposedName).pathExtension
        return proposedExtension.isEmpty ? "\(proposedName).\(originalExtension)" : proposedName
    }

    private func chooseDestinationDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = AppLocalization.string("Send")

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    private func applySettingsChange() {
        let settings = DropShelfSettings.snapshot()
        trimToMaxItemCount(settings.maxItemCount)
        shakeMonitor.update(settings: settings)
        panelController.refreshIfVisible()
    }

    private func trimToMaxItemCount(_ maxItemCount: Int) {
        guard items.count > maxItemCount else {
            return
        }

        items.removeLast(items.count - maxItemCount)
    }

    private func showToast(_ message: String, systemImage: String = "checkmark.circle.fill") {
        let controller = toastController ?? ToastPanelController()
        toastController = controller
        controller.show(message: message, systemImage: systemImage)
    }
}
