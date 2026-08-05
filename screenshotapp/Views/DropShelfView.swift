import AppKit
import SwiftUI

struct DropShelfView: View {
    @ObservedObject var store: DropShelfStore

    @AppStorage(DropShelfSettings.Keys.layoutMode)
    private var layoutModeRaw = DropShelfSettings.defaultLayoutMode.rawValue

    @AppStorage(DropShelfSettings.Keys.itemSize)
    private var itemSizeRaw = DropShelfSettings.defaultItemSize.rawValue

    @AppStorage(DropShelfSettings.Keys.customItemWidth)
    private var customItemWidth = DropShelfSettings.defaultCustomItemWidth

    @AppStorage(ToolboxSettings.Keys.language)
    private var languageRaw = ToolboxSettings.defaultLanguage.rawValue

    static let outerPadding: CGFloat = 12
    static let headerHeight: CGFloat = 46
    static let gridSpacing: CGFloat = 12
    static let visibleStackLimit = 5

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: Self.headerHeight)

            Divider()
                .opacity(0.45)

            content
                .padding(Self.outerPadding)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(store.isDropTargeted ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: store.isDropTargeted ? 2 : 1)
        }
        .animation(.easeOut(duration: 0.12), value: store.isDropTargeted)
        .environment(\.locale, selectedLanguage.locale)
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? ToolboxSettings.defaultLanguage
    }

    private var itemSize: CGSize {
        let size = DropShelfItemSize(rawValue: itemSizeRaw) ?? DropShelfSettings.defaultItemSize
        let customWidth = DropShelfSettings.clampedCustomItemWidth(customItemWidth)

        return size.size(customWidth: customWidth)
    }

    private var layoutMode: DropShelfLayoutMode {
        DropShelfLayoutMode(rawValue: layoutModeRaw) ?? DropShelfSettings.defaultLayoutMode
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                HStack(spacing: 10) {
                    Label(AppLocalization.string("Drop Shelf"), systemImage: "tray.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Text("\(store.items.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer(minLength: 0)
                }

                WindowDragHandle()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .help(Text(AppLocalization.string("Move shelf")))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            DropShelfIconButton(systemName: "paperplane", help: AppLocalization.string("Send All")) {
                store.sendAll()
            }
            .disabled(store.items.isEmpty)

            DropShelfIconButton(systemName: "trash", help: AppLocalization.string("Clear")) {
                store.clearAll()
            }
            .disabled(store.items.isEmpty)

            DropShelfIconButton(systemName: "xmark", help: AppLocalization.string("Close")) {
                store.hideShelf()
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            EmptyDropShelfView(isTargeted: store.isDropTargeted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch layoutMode {
            case .stack:
                stackContent
            case .grid:
                gridContent
            }
        }
    }

    private var stackContent: some View {
        ZStack {
            ForEach(Array(visibleStackItems.enumerated()), id: \.element.id) { index, item in
                dropShelfItemCard(
                    for: item,
                    stackDepth: visibleStackItems.count - index - 1,
                    dragPasteboardWriters: { store.draggingPasteboardWritersForAllItems() }
                )
                .zIndex(Double(index))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if hiddenStackCount > 0 {
                Text("+\(hiddenStackCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(4)
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Self.gridSpacing) {
                ForEach(store.items) { item in
                    dropShelfItemCard(
                        for: item,
                        stackDepth: 0,
                        dragPasteboardWriters: {
                            guard let writer = store.draggingPasteboardWriter(for: item) else {
                                return []
                            }

                            return [writer]
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(itemSize.width), spacing: Self.gridSpacing), count: Self.gridColumnCount)
    }

    static let gridColumnCount = 2

    private var visibleStackItems: [DropShelfItem] {
        Array(store.items.suffix(Self.visibleStackLimit))
    }

    private var hiddenStackCount: Int {
        max(0, store.items.count - Self.visibleStackLimit)
    }

    private func dropShelfItemCard(
        for item: DropShelfItem,
        stackDepth: Int,
        dragPasteboardWriters: @escaping () -> [NSPasteboardWriting]
    ) -> some View {
        DropShelfItemCard(
            item: item,
            itemSize: itemSize,
            stackDepth: stackDepth,
            previewAction: { store.preview(item) },
            renameAction: { store.rename(item, to: $0) },
            copyAction: { store.copy(item) },
            sendAction: { store.send(item) },
            removeAction: { store.remove(item) },
            moveBackwardAction: { store.moveItemBackward(item) },
            moveForwardAction: { store.moveItemForward(item) },
            dragPasteboardWriters: dragPasteboardWriters,
            dragStarted: { store.beginInternalDrag() },
            dragEnded: { store.endInternalDrag() }
        )
    }
}

private struct EmptyDropShelfView: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

            Text(isTargeted ? AppLocalization.string("Release to add") : AppLocalization.string("Drop items here"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

private struct DropShelfItemCard: View {
    let item: DropShelfItem
    let itemSize: CGSize
    let stackDepth: Int
    let previewAction: () -> Void
    let renameAction: (String) -> Void
    let copyAction: () -> Void
    let sendAction: () -> Void
    let removeAction: () -> Void
    let moveBackwardAction: () -> Void
    let moveForwardAction: () -> Void
    let dragPasteboardWriters: () -> [NSPasteboardWriting]
    let dragStarted: () -> Void
    let dragEnded: () -> Void

    @State private var draftName: String

    init(
        item: DropShelfItem,
        itemSize: CGSize,
        stackDepth: Int,
        previewAction: @escaping () -> Void,
        renameAction: @escaping (String) -> Void,
        copyAction: @escaping () -> Void,
        sendAction: @escaping () -> Void,
        removeAction: @escaping () -> Void,
        moveBackwardAction: @escaping () -> Void,
        moveForwardAction: @escaping () -> Void,
        dragPasteboardWriters: @escaping () -> [NSPasteboardWriting],
        dragStarted: @escaping () -> Void,
        dragEnded: @escaping () -> Void
    ) {
        self.item = item
        self.itemSize = itemSize
        self.stackDepth = stackDepth
        self.previewAction = previewAction
        self.renameAction = renameAction
        self.copyAction = copyAction
        self.sendAction = sendAction
        self.removeAction = removeAction
        self.moveBackwardAction = moveBackwardAction
        self.moveForwardAction = moveForwardAction
        self.dragPasteboardWriters = dragPasteboardWriters
        self.dragStarted = dragStarted
        self.dragEnded = dragEnded
        _draftName = State(initialValue: item.displayName)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.55))

                previewImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)

                DropShelfDragInteractionView(
                    dragImage: dragImage,
                    previewAction: previewAction,
                    pasteboardWriters: dragPasteboardWriters,
                    dragStarted: dragStarted,
                    dragEnded: dragEnded
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    Spacer()

                    DropShelfIconButton(
                        systemName: "xmark",
                        help: AppLocalization.string("Remove"),
                        action: removeAction
                    )
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(6)
            }
            .frame(height: max(62, itemSize.height - 52))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture(perform: previewAction)

            VStack(alignment: .leading, spacing: 2) {
                TextField(AppLocalization.string("Name"), text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .onSubmit {
                        renameAction(draftName)
                    }

                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(8)
        .frame(width: itemSize.width, height: itemSize.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .rotationEffect(.degrees(rotationDegrees))
        .offset(stackOffset)
        .shadow(color: .black.opacity(0.20), radius: 12, y: 8)
        .contextMenu {
            Button {
                previewAction()
            } label: {
                Label(AppLocalization.string("Preview"), systemImage: "eye")
            }

            Button {
                copyAction()
            } label: {
                Label(AppLocalization.string("Copy"), systemImage: "doc.on.doc")
            }

            Button {
                sendAction()
            } label: {
                Label(AppLocalization.string("Send To..."), systemImage: "paperplane")
            }

            Divider()

            Button {
                moveBackwardAction()
            } label: {
                Label(AppLocalization.string("Move Backward"), systemImage: "arrow.left")
            }

            Button {
                moveForwardAction()
            } label: {
                Label(AppLocalization.string("Move Forward"), systemImage: "arrow.right")
            }

            Divider()

            Button(role: .destructive) {
                removeAction()
            } label: {
                Label(AppLocalization.string("Remove"), systemImage: "xmark")
            }
        }
        .onChange(of: item.displayName) { _, newValue in
            draftName = newValue
        }
    }

    private var stackOffset: CGSize {
        CGSize(
            width: CGFloat(stackDepth) * -8,
            height: CGFloat(stackDepth) * 7
        )
    }

    private var rotationDegrees: Double {
        guard stackDepth > 0 else {
            return 0
        }

        return stackDepth.isMultiple(of: 2) ? -2.5 : 2.0
    }

    private var previewImage: Image {
        if let image = item.image {
            return Image(nsImage: image)
        }

        if let fileURL = item.fileURL {
            if !fileURL.hasDirectoryPath,
               let image = NSImage(contentsOf: fileURL),
               image.isValid {
                return Image(nsImage: image)
            }

            return Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
        }

        return Image(systemName: item.kind.systemImage)
    }

    private var dragImage: NSImage {
        if let image = item.image {
            return image
        }

        if let fileURL = item.fileURL {
            if !fileURL.hasDirectoryPath,
               let image = NSImage(contentsOf: fileURL),
               image.isValid {
                return image
            }

            return NSWorkspace.shared.icon(forFile: fileURL.path)
        }

        return NSImage(systemSymbolName: item.kind.systemImage, accessibilityDescription: nil)
            ?? NSImage(size: CGSize(width: 64, height: 64))
    }
}

private struct DropShelfIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        .help(help)
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragHandleNSView {
        WindowDragHandleNSView()
    }

    func updateNSView(_ nsView: WindowDragHandleNSView, context: Context) {}
}

private final class WindowDragHandleNSView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct DropShelfDragInteractionView: NSViewRepresentable {
    let dragImage: NSImage
    let previewAction: () -> Void
    let pasteboardWriters: () -> [NSPasteboardWriting]
    let dragStarted: () -> Void
    let dragEnded: () -> Void

    func makeNSView(context: Context) -> DropShelfDragInteractionNSView {
        let view = DropShelfDragInteractionNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: DropShelfDragInteractionNSView, context: Context) {
        nsView.dragImage = dragImage
        nsView.previewAction = previewAction
        nsView.pasteboardWriters = pasteboardWriters
        nsView.dragStarted = dragStarted
        nsView.dragEnded = dragEnded
    }
}

private final class DropShelfDragInteractionNSView: NSView, NSDraggingSource {
    var dragImage = NSImage(size: CGSize(width: 64, height: 64))
    var previewAction: () -> Void = {}
    var pasteboardWriters: () -> [NSPasteboardWriting] = { [] }
    var dragStarted: () -> Void = {}
    var dragEnded: () -> Void = {}

    private var initialPoint: NSPoint?
    private var didBeginDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        initialPoint = event.locationInWindow
        didBeginDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialPoint, !didBeginDrag else {
            return
        }

        let deltaX = event.locationInWindow.x - initialPoint.x
        let deltaY = event.locationInWindow.y - initialPoint.y
        guard hypot(deltaX, deltaY) >= 4 else {
            return
        }

        let writers = pasteboardWriters()
        guard !writers.isEmpty else {
            return
        }

        didBeginDrag = true
        dragStarted()

        let draggingItems = writers.enumerated().map { index, writer in
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            draggingItem.setDraggingFrame(
                draggingFrame(for: index),
                contents: dragImage
            )
            return draggingItem
        }

        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    override func mouseUp(with event: NSEvent) {
        if !didBeginDrag {
            previewAction()
        }

        initialPoint = nil
        didBeginDrag = false
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        dragEnded()
        initialPoint = nil
        didBeginDrag = false
    }

    private func draggingFrame(for index: Int) -> NSRect {
        let offset = CGFloat(min(index, 4)) * 7
        return bounds.offsetBy(dx: offset, dy: -offset)
    }
}
