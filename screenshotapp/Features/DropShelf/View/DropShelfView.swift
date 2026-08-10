import AppKit
import SwiftUI

struct DropShelfView: View {
    @ObservedObject var store: DropShelfViewModel

    @AppStorage(DropShelfSettings.Keys.layoutMode)
    private var layoutModeRaw = DropShelfSettings.defaultLayoutMode.rawValue

    @AppStorage(DropShelfSettings.Keys.itemSize)
    private var itemSizeRaw = DropShelfSettings.defaultItemSize.rawValue

    @AppStorage(DropShelfSettings.Keys.customItemWidth)
    private var customItemWidth = DropShelfSettings.defaultCustomItemWidth

    @AppStorage(DropShelfSettings.Keys.gridColumnCount)
    private var gridColumnCount = DropShelfSettings.defaultGridColumnCount

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

    @ViewBuilder
    private var header: some View {
        if store.selectedItemIDs.isEmpty {
            defaultHeader
        } else {
            selectionHeader
        }
    }

    private var defaultHeader: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text(AppLocalization.string("Drop Shelf"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    if !store.items.isEmpty {
                        Text("\(store.items.count)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }

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

    private var selectionHeader: some View {
        HStack(spacing: 10) {
            DropShelfIconButton(
                systemName: "xmark.circle.fill",
                help: AppLocalization.string("Clear Selection")
            ) {
                store.clearSelection()
            }

            Text(AppLocalization.formatted("%ld selected", store.selectedItemIDs.count))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .monospacedDigit()

            Spacer(minLength: 0)

            DropShelfIconButton(systemName: "doc.on.doc", help: AppLocalization.string("Copy")) {
                store.copySelection()
            }

            DropShelfIconButton(systemName: "paperplane", help: AppLocalization.string("Send To...")) {
                store.sendSelection()
            }

            DropShelfIconButton(systemName: "trash", help: AppLocalization.string("Remove")) {
                store.removeSelection()
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
            case .list:
                listContent
            }
        }
    }

    private var stackContent: some View {
        ZStack {
            ForEach(Array(visibleStackItems.enumerated()), id: \.element.id) { index, item in
                dropShelfItemCard(
                    for: item,
                    stackDepth: visibleStackItems.count - index - 1,
                    selectable: false,
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
                        selectable: true,
                        dragPasteboardWriters: { store.draggingPasteboardWriters(forDraggedItem: item) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(itemSize.width), spacing: Self.gridSpacing),
            count: resolvedGridColumnCount
        )
    }

    private var resolvedGridColumnCount: Int {
        DropShelfSettings.clampedGridColumnCount(gridColumnCount)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.items) { item in
                    DropShelfListRow(
                        item: item,
                        isSelected: store.isSelected(item),
                        toggleSelection: { store.toggleSelection(item) },
                        previewAction: { store.preview(item) },
                        copyAction: { store.copy(item) },
                        sendAction: { store.send(item) },
                        removeAction: { store.remove(item) },
                        dragPasteboardWriters: { store.draggingPasteboardWriters(forDraggedItem: item) },
                        dragStarted: { store.beginInternalDrag() },
                        dragEnded: { store.endInternalDrag() }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleStackItems: [DropShelfItem] {
        Array(store.items.suffix(Self.visibleStackLimit))
    }

    private var hiddenStackCount: Int {
        max(0, store.items.count - Self.visibleStackLimit)
    }

    private func dropShelfItemCard(
        for item: DropShelfItem,
        stackDepth: Int,
        selectable: Bool,
        dragPasteboardWriters: @escaping () -> [NSPasteboardWriting]
    ) -> some View {
        DropShelfItemCard(
            item: item,
            itemSize: itemSize,
            stackDepth: stackDepth,
            selectable: selectable,
            isSelected: store.isSelected(item),
            toggleSelection: { store.toggleSelection(item) },
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
        VStack(spacing: 9) {
            Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                .symbolEffect(.bounce, value: isTargeted)

            Text(isTargeted ? AppLocalization.string("Release to add") : AppLocalization.string("Drop items here"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

            Text(AppLocalization.string("Files, folders, links, text, and images"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
                .foregroundStyle(
                    isTargeted ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.28)
                )
        )
        .padding(4)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

private struct DropShelfItemCard: View {
    let item: DropShelfItem
    let itemSize: CGSize
    let stackDepth: Int
    let selectable: Bool
    let isSelected: Bool
    let toggleSelection: () -> Void
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
    @State private var isHovering = false

    init(
        item: DropShelfItem,
        itemSize: CGSize,
        stackDepth: Int,
        selectable: Bool,
        isSelected: Bool,
        toggleSelection: @escaping () -> Void,
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
        self.selectable = selectable
        self.isSelected = isSelected
        self.toggleSelection = toggleSelection
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

    private static let footerHeight: CGFloat = 44

    private var mediaHeight: CGFloat {
        max(48, itemSize.height - Self.footerHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            media
                .frame(width: itemSize.width, height: mediaHeight)
                .clipped()

            footer
                .frame(width: itemSize.width, height: Self.footerHeight)
                .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        }
        .frame(width: itemSize.width, height: itemSize.height)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.accentColor : .white.opacity(isHovering ? 0.2 : 0.08),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .offset(isHovering ? .zero : stackOffset)
        .scaleEffect(isHovering ? 1.03 : stackScale)
        .opacity(isHovering ? 1 : stackOpacity)
        .shadow(
            color: .black.opacity(isHovering ? 0.3 : stackShadowOpacity),
            radius: isHovering ? 18 : 9,
            y: isHovering ? 12 : 5
        )
        .zIndex(isHovering ? 10 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isHovering)
        .onHover { isHovering = $0 }
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

    // The image/icon area. Fills its region; the parent clips it. The drag/click
    // layer covers only this area, so the footer's name field stays editable.
    private var media: some View {
        ZStack {
            if item.isImageBacked {
                Color.black.opacity(0.2)

                item.previewImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                item.kindTint.opacity(0.14)

                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(item.kindTint)
            }

            DropShelfDragInteractionView(
                dragImage: item.dragImage,
                selectAction: selectable ? toggleSelection : previewAction,
                previewAction: previewAction,
                pasteboardWriters: dragPasteboardWriters,
                dragStarted: dragStarted,
                dragEnded: dragEnded
            )

            VStack {
                HStack(alignment: .top) {
                    if selectable && isSelected {
                        DropShelfSelectedBadge()
                    }

                    Spacer()

                    if isHovering {
                        DropShelfIconButton(
                            systemName: "xmark",
                            help: AppLocalization.string("Remove"),
                            action: removeAction
                        )
                    }
                }

                Spacer()
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(item.kindTint)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                TextField(AppLocalization.string("Name"), text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .onSubmit { renameAction(draftName) }

                Text(item.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    // A clean downward-right cascade: deeper cards sit lower, slightly smaller,
    // dimmer, and with a softer shadow so the stack reads as depth without the
    // muddy overlap of rotated cards.
    private var stackOffset: CGSize {
        CGSize(
            width: CGFloat(stackDepth) * 7,
            height: CGFloat(stackDepth) * 11
        )
    }

    private var stackScale: CGFloat {
        max(0.9, 1 - CGFloat(stackDepth) * 0.04)
    }

    private var stackOpacity: Double {
        max(0.5, 1 - Double(stackDepth) * 0.16)
    }

    private var stackShadowOpacity: Double {
        max(0.05, 0.16 - Double(stackDepth) * 0.03)
    }
}

// Shared visuals for both the card and list-row presentations, so a file, image,
// folder, link, or text renders the same everywhere.
private extension DropShelfItem {
    var kindTint: Color {
        switch kind {
        case .file: .gray
        case .folder: .blue
        case .image: .green
        case .link: .purple
        case .text: .orange
        }
    }

    var isImageBacked: Bool {
        if image != nil {
            return true
        }

        if let fileURL,
           !fileURL.hasDirectoryPath,
           let image = NSImage(contentsOf: fileURL),
           image.isValid {
            return true
        }

        return false
    }

    var previewImage: Image {
        if let image {
            return Image(nsImage: image)
        }

        if let fileURL {
            if !fileURL.hasDirectoryPath,
               let image = NSImage(contentsOf: fileURL),
               image.isValid {
                return Image(nsImage: image)
            }

            return Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
        }

        return Image(systemName: kind.systemImage)
    }

    var dragImage: NSImage {
        if let image {
            return image
        }

        if let fileURL {
            if !fileURL.hasDirectoryPath,
               let image = NSImage(contentsOf: fileURL),
               image.isValid {
                return image
            }

            return NSWorkspace.shared.icon(forFile: fileURL.path)
        }

        return NSImage(systemSymbolName: kind.systemImage, accessibilityDescription: nil)
            ?? NSImage(size: CGSize(width: 64, height: 64))
    }
}

private struct DropShelfListRow: View {
    let item: DropShelfItem
    let isSelected: Bool
    let toggleSelection: () -> Void
    let previewAction: () -> Void
    let copyAction: () -> Void
    let sendAction: () -> Void
    let removeAction: () -> Void
    let dragPasteboardWriters: () -> [NSPasteboardWriting]
    let dragStarted: () -> Void
    let dragEnded: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                thumbnail
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.35))
                                .overlay { DropShelfSelectedBadge().scaleEffect(0.8) }
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 108)
            }

            // Drag/click layer sits above the content but below the buttons below.
            DropShelfDragInteractionView(
                dragImage: item.dragImage,
                selectAction: toggleSelection,
                previewAction: previewAction,
                pasteboardWriters: dragPasteboardWriters,
                dragStarted: dragStarted,
                dragEnded: dragEnded
            )

            HStack(spacing: 4) {
                Spacer()

                if isHovering {
                    DropShelfIconButton(
                        systemName: "eye",
                        help: AppLocalization.string("Preview"),
                        action: previewAction
                    )

                    DropShelfIconButton(
                        systemName: "doc.on.doc",
                        help: AppLocalization.string("Copy"),
                        action: copyAction
                    )

                    DropShelfIconButton(
                        systemName: "paperplane",
                        help: AppLocalization.string("Send To..."),
                        action: sendAction
                    )
                }

                DropShelfIconButton(
                    systemName: "xmark",
                    help: AppLocalization.string("Remove"),
                    action: removeAction
                )
                .opacity(isHovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.16)
                : Color.primary.opacity(isHovering ? 0.08 : 0.03),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? Color.accentColor : .white.opacity(isHovering ? 0.16 : 0.06),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(action: previewAction) {
                Label(AppLocalization.string("Preview"), systemImage: "eye")
            }

            Button(action: copyAction) {
                Label(AppLocalization.string("Copy"), systemImage: "doc.on.doc")
            }

            Button(action: sendAction) {
                Label(AppLocalization.string("Send To..."), systemImage: "paperplane")
            }

            Divider()

            Button(role: .destructive, action: removeAction) {
                Label(AppLocalization.string("Remove"), systemImage: "xmark")
            }
        }
    }

    private var thumbnail: some View {
        ZStack {
            if item.isImageBacked {
                item.previewImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                item.kindTint.opacity(0.16)

                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(item.kindTint)
            }
        }
    }
}

/// Passive "selected" indicator. Selection is toggled by clicking the item body,
/// so this is a badge, not a control.
private struct DropShelfSelectedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white, Color.accentColor)
            .background(Circle().fill(.white).padding(3))
            .shadow(color: .black.opacity(0.3), radius: 2)
    }
}

private struct DropShelfIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Color.primary.opacity(isHovering ? 0.14 : 0.06),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .onHover { isHovering = $0 }
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
    var selectAction: () -> Void = {}
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
        nsView.selectAction = selectAction
        nsView.previewAction = previewAction
        nsView.pasteboardWriters = pasteboardWriters
        nsView.dragStarted = dragStarted
        nsView.dragEnded = dragEnded
    }
}

private final class DropShelfDragInteractionNSView: NSView, NSDraggingSource {
    var dragImage = NSImage(size: CGSize(width: 64, height: 64))
    var selectAction: () -> Void = {}
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
            // Single click toggles selection; double click opens a preview. On the
            // double click, revert the toggle the first click already applied so the
            // selection is left unchanged.
            if event.clickCount >= 2 {
                selectAction()
                previewAction()
            } else {
                selectAction()
            }
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
