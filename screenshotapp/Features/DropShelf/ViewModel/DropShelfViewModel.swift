import AppKit
import Combine
import KeyboardShortcuts

@MainActor
final class DropShelfViewModel: ObservableObject, ShelfCollecting {
    @Published private(set) var items: [DropShelfItem] = []
    @Published private(set) var selectedItemIDs: Set<UUID> = []
    @Published private(set) var isShelfVisible = false
    @Published private(set) var isDropTargeted = false
    @Published private(set) var isInternalDragInProgress = false

    private var defaultsObserver: AnyCancellable?
    private var activeObserver: AnyCancellable?
    private let shakeMonitor = DropShelfShakeMonitor()
    weak var presenter: DropShelfPresenting?
    private let exporter: DropShelfExporting
    private let settings: DropShelfSettingsReading & ToolboxSettingsReading
    private let toastPresenter: ToastPresenting
    private let folderPicker: FolderPicking

    init(
        exporter: DropShelfExporting,
        settings: DropShelfSettingsReading & ToolboxSettingsReading,
        toastPresenter: ToastPresenting,
        folderPicker: FolderPicking
    ) {
        self.exporter = exporter
        self.settings = settings
        self.toastPresenter = toastPresenter
        self.folderPicker = folderPicker

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
        guard settings.isToolEnabled(.dropShelf) else { return }
        isShelfVisible = true
        presenter?.refresh()
    }

    func hideShelf() {
        isShelfVisible = false
        isDropTargeted = false
        isInternalDragInProgress = false
        items.removeAll()
        selectedItemIDs.removeAll()
        presenter?.hide()
    }

    func toggleShelf() {
        if isShelfVisible {
            hideShelf()
        } else {
            showShelf()
        }
    }

    func addItems(from pasteboard: NSPasteboard) -> Bool {
        guard settings.isToolEnabled(.dropShelf) else {
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

        let settings = settings.dropShelfSettings()
        items.append(contentsOf: newItems)
        trimToMaxItemCount(settings.maxItemCount)
        isShelfVisible = true
        isDropTargeted = false
        presenter?.refresh()
        showToast(
            newItems.count == 1
                ? AppLocalization.formatted("Added %ld item", newItems.count)
                : AppLocalization.formatted("Added %ld items", newItems.count)
        )
        return true
    }

    /// Adds a captured screenshot image to the shelf and reveals it.
    func addScreenshot(_ image: NSImage, name: String) {
        guard settings.isToolEnabled(.dropShelf) else {
            NSSound.beep()
            showToast(
                AppLocalization.string("Enable Drop Shelf first"),
                systemImage: "exclamationmark.triangle.fill"
            )
            return
        }

        let item = DropShelfItem(kind: .image, displayName: name, image: image)
        let settings = settings.dropShelfSettings()
        items.append(item)
        trimToMaxItemCount(settings.maxItemCount)
        isShelfVisible = true
        presenter?.refresh()
        showToast(AppLocalization.formatted("Added %ld item", 1))
    }

    func addFile(_ url: URL) {
        guard settings.isToolEnabled(.dropShelf) else {
            NSSound.beep()
            showToast(
                AppLocalization.string("Enable Drop Shelf first"),
                systemImage: "exclamationmark.triangle.fill"
            )
            return
        }

        let item = DropShelfItem(
            kind: .file,
            displayName: url.lastPathComponent,
            fileURL: url
        )
        let settings = settings.dropShelfSettings()
        items.append(item)
        trimToMaxItemCount(settings.maxItemCount)
        isShelfVisible = true
        presenter?.refresh()
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
        selectedItemIDs.remove(item.id)
        presenter?.refreshIfVisible()
    }

    func clearAll() {
        guard !items.isEmpty else {
            return
        }

        items.removeAll()
        selectedItemIDs.removeAll()
        presenter?.refreshIfVisible()
    }

    func preview(_ item: DropShelfItem) {
        do {
            if let url = item.url {
                NSWorkspace.shared.open(url)
                return
            }

            let url = try exporter.previewURL(for: item)
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
            let exportedURLs = try exporter.export(items, to: directoryURL)
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
            _ = try exporter.export([item], to: directoryURL)
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
            let url = try exporter.previewURL(for: item)
            return url as NSURL
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not drag item"), systemImage: "exclamationmark.triangle.fill")
            return nil
        }
    }

    func draggingPasteboardWritersForAllItems() -> [NSPasteboardWriting] {
        do {
            return try exporter.draggingURLs(for: items).map { $0 as NSURL }
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
            presenter?.refreshIfVisible()
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
        presenter?.refreshIfVisible()
    }

    func moveItemBackward(_ item: DropShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              index > 0 else {
            return
        }

        items.swapAt(index, index - 1)
        presenter?.refreshIfVisible()
    }

    func moveItemForward(_ item: DropShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              index < items.count - 1 else {
            return
        }

        items.swapAt(index, index + 1)
        presenter?.refreshIfVisible()
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
            presenter?.refreshIfVisible()
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
        folderPicker.pickDirectory(prompt: AppLocalization.string("Send"), canCreate: true)
    }

    private func applySettingsChange() {
        let settings = settings.dropShelfSettings()
        trimToMaxItemCount(settings.maxItemCount)
        shakeMonitor.update(settings: settings)
        presenter?.refreshIfVisible()
    }

    private func trimToMaxItemCount(_ maxItemCount: Int) {
        guard items.count > maxItemCount else {
            return
        }

        items.removeLast(items.count - maxItemCount)
        selectedItemIDs.formIntersection(items.map(\.id))
    }

    private func showToast(_ message: String, systemImage: String = "checkmark.circle.fill") {
        toastPresenter.show(message, systemImage: systemImage)
    }
}

// MARK: - Multi-selection (grid & list)

extension DropShelfViewModel {
    var selectedItems: [DropShelfItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    func isSelected(_ item: DropShelfItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func toggleSelection(_ item: DropShelfItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func selectAll() {
        selectedItemIDs = Set(items.map(\.id))
    }

    func clearSelection() {
        selectedItemIDs.removeAll()
    }

    /// Items that a drag starting on `item` should carry: the whole selection when
    /// `item` is part of a multi-selection, otherwise just `item` (Finder-style).
    func draggingPasteboardWriters(forDraggedItem item: DropShelfItem) -> [NSPasteboardWriting] {
        guard selectedItemIDs.contains(item.id), selectedItemIDs.count > 1 else {
            return draggingPasteboardWriter(for: item).map { [$0] } ?? []
        }

        do {
            return try exporter.draggingURLs(for: selectedItems).map { $0 as NSURL }
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not drag items"), systemImage: "exclamationmark.triangle.fill")
            return []
        }
    }

    func copySelection() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }

        do {
            let urls = try exporter.draggingURLs(for: targets).map { $0 as NSURL }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(urls)
            showToast(AppLocalization.formatted("Copied %ld items", targets.count))
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not copy items"), systemImage: "exclamationmark.triangle.fill")
        }
    }

    func sendSelection() {
        let targets = selectedItems
        guard !targets.isEmpty, let directoryURL = chooseDestinationDirectory() else { return }

        do {
            let exportedURLs = try exporter.export(targets, to: directoryURL)
            showToast(AppLocalization.formatted("Sent %ld items", exportedURLs.count))
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not send items"), systemImage: "exclamationmark.triangle.fill")
        }
    }

    func removeSelection() {
        guard !selectedItemIDs.isEmpty else { return }

        items.removeAll { selectedItemIDs.contains($0.id) }
        selectedItemIDs.removeAll()
        presenter?.refreshIfVisible()
    }
}
