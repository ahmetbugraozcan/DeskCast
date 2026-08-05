import AppKit
import SwiftUI

struct ScreenshotShelfView: View {
    @ObservedObject var store: ScreenshotShelfViewModel
    @State private var activeDropIndex: Int?
    @State private var reorderDrag: ScreenshotReorderDrag?
    @State private var thumbnailScreenFrames: [UUID: CGRect] = [:]

    @AppStorage(ScreenshotShelfSettings.Keys.stackDirection)
    private var stackDirectionRaw = ScreenshotShelfSettings.defaultStackDirection.rawValue

    @AppStorage(ScreenshotShelfSettings.Keys.thumbnailSize)
    private var thumbnailSizeRaw = ScreenshotShelfSettings.defaultThumbnailSize.rawValue

    @AppStorage(ScreenshotShelfSettings.Keys.customThumbnailWidth)
    private var customThumbnailWidth = ScreenshotShelfSettings.defaultCustomThumbnailWidth

    @AppStorage(ScreenshotShelfSettings.Keys.thumbnailAspectRatio)
    private var thumbnailAspectRatioRaw = ScreenshotShelfSettings.defaultThumbnailAspectRatio.rawValue

    @AppStorage(ScreenshotShelfSettings.Keys.customThumbnailAspectWidth)
    private var customThumbnailAspectWidth = ScreenshotShelfSettings.defaultCustomThumbnailAspectWidth

    @AppStorage(ScreenshotShelfSettings.Keys.customThumbnailAspectHeight)
    private var customThumbnailAspectHeight = ScreenshotShelfSettings.defaultCustomThumbnailAspectHeight

    @AppStorage(ScreenshotShelfSettings.Keys.exportFilenamePrefix)
    private var exportFilenamePrefix = ScreenshotShelfSettings.defaultExportFilenamePrefix

    @AppStorage(ScreenshotShelfSettings.Keys.exportFilenameVariants)
    private var exportFilenameVariants = ScreenshotShelfSettings.defaultExportFilenameVariants

    @AppStorage(ScreenshotShelfSettings.Keys.autoSaveCapturedScreenshots)
    private var autoSaveCapturedScreenshots = ScreenshotShelfSettings.defaultAutoSaveCapturedScreenshots

    @AppStorage(ToolboxSettings.Keys.language)
    private var languageRaw = ToolboxSettings.defaultLanguage.rawValue

    var body: some View {
        ScrollView(scrollAxis, showsIndicators: false) {
            shelfContent
        }
        .environment(\.locale, selectedLanguage.locale)
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? ToolboxSettings.defaultLanguage
    }

    static let outerPadding: CGFloat = 12
    static let cardPadding: CGFloat = 0
    static let thumbnailSpacing: CGFloat = 24
    static let insertionIndicatorThickness: CGFloat = 4

    private var stackDirection: StackDirection {
        StackDirection(rawValue: stackDirectionRaw) ?? ScreenshotShelfSettings.defaultStackDirection
    }

    private var thumbnailSize: CGSize {
        let size = ShelfThumbnailSize(rawValue: thumbnailSizeRaw) ?? ScreenshotShelfSettings.defaultThumbnailSize
        let customWidth = ScreenshotShelfSettings.clampedCustomThumbnailWidth(customThumbnailWidth)

        return size.size(customWidth: customWidth, aspectRatio: thumbnailAspectRatio)
    }

    private var thumbnailAspectRatio: CGFloat {
        let ratio = ShelfThumbnailAspectRatio(rawValue: thumbnailAspectRatioRaw)
            ?? ScreenshotShelfSettings.defaultThumbnailAspectRatio

        return ratio.value(
            customWidth: ScreenshotShelfSettings.clampedAspectComponent(customThumbnailAspectWidth),
            customHeight: ScreenshotShelfSettings.clampedAspectComponent(customThumbnailAspectHeight)
        )
    }

    private var exportOptions: [ScreenshotExportOption] {
        ScreenshotExportNaming.options(
            prefix: exportFilenamePrefix,
            variants: exportFilenameVariants
        )
    }

    private var scrollAxis: Axis.Set {
        stackDirection == .horizontal ? .horizontal : .vertical
    }

    private var insertionIndicatorSize: CGSize {
        let cardSize = Self.cardSize(for: thumbnailSize)

        switch stackDirection {
        case .horizontal:
            return CGSize(width: Self.insertionIndicatorThickness, height: cardSize.height)
        case .vertical:
            return CGSize(width: cardSize.width, height: Self.insertionIndicatorThickness)
        }
    }

    private var shelfContent: some View {
        stackContent
            .padding(Self.outerPadding)
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                if let activeDropIndex {
                    ShelfInsertionIndicator(stackDirection: stackDirection)
                        .frame(
                            width: insertionIndicatorSize.width,
                            height: insertionIndicatorSize.height
                        )
                        .position(insertionIndicatorPosition(for: activeDropIndex))
                        .transition(.opacity)
                }
            }
            .animation(
                .spring(response: 0.22, dampingFraction: 0.86),
                value: store.screenshots.map(\.id)
            )
            .animation(.easeOut(duration: 0.12), value: activeDropIndex)
    }

    @ViewBuilder
    private var stackContent: some View {
        if stackDirection == .horizontal {
            HStack(spacing: Self.thumbnailSpacing) {
                thumbnails
            }
        } else {
            VStack(spacing: Self.thumbnailSpacing) {
                thumbnails
            }
        }
    }

    @ViewBuilder
    private var thumbnails: some View {
        ForEach(store.screenshots) { item in
            ScreenshotThumbnailView(
                item: item,
                thumbnailSize: thumbnailSize,
                stackDirection: stackDirection,
                autoSaveEnabled: autoSaveCapturedScreenshots,
                closeAction: { store.remove(item) },
                closeAllAction: { store.clearAll() },
                copyAction: { store.copy(item) },
                copyTextAction: { store.copyRecognizedText(item) },
                addToShelfAction: { store.addToShelf(item) },
                showInFinderAction: { store.showInFinder(item) },
                saveAsAction: { store.saveAs(item) },
                quickSaveAction: { store.quickSave(item) },
                saveExportAction: { option in store.save(item, exportOption: option) },
                pinAction: { store.togglePin(item) },
                openAction: { store.openInPreview(item) },
                dragPasteboardWriter: { store.draggingPasteboardWriter(for: item) },
                exportOptions: exportOptions,
                screenFrameChanged: { itemID, frame in
                    updateThumbnailScreenFrame(itemID: itemID, frame: frame)
                },
                reorderChanged: { update in
                    updateReorderDrag(for: item, update: update)
                },
                reorderEnded: { update, didCompleteExternalDrop in
                    if didCompleteExternalDrop {
                        clearReorderState()
                    } else {
                        completeReorderDrag(for: item, update: update)
                    }
                }
            )
            .offset(reorderOffset(for: item.id))
            .zIndex(reorderDrag?.itemID == item.id ? 1 : 0)
            .animation(nil, value: reorderDrag?.translation ?? 0)
        }
    }

    static func cardSize(for thumbnailSize: CGSize) -> CGSize {
        CGSize(
            width: thumbnailSize.width + cardPadding * 2,
            height: thumbnailSize.height + cardPadding * 2
        )
    }

    private func insertionIndicatorPosition(for index: Int) -> CGPoint {
        let cardSize = Self.cardSize(for: thumbnailSize)
        let count = store.screenshots.count
        let clampedIndex = min(max(index, 0), count)

        switch stackDirection {
        case .horizontal:
            return CGPoint(
                x: Self.outerPadding + insertionOffset(
                    at: clampedIndex,
                    itemLength: cardSize.width,
                    itemCount: count
                ),
                y: Self.outerPadding + cardSize.height / 2
            )
        case .vertical:
            return CGPoint(
                x: Self.outerPadding + cardSize.width / 2,
                y: Self.outerPadding + insertionOffset(
                    at: clampedIndex,
                    itemLength: cardSize.height,
                    itemCount: count
                )
            )
        }
    }

    private func insertionOffset(at index: Int, itemLength: CGFloat, itemCount: Int) -> CGFloat {
        guard itemCount > 0 else {
            return 0
        }

        if index == 0 {
            return Self.insertionIndicatorThickness / 2
        }

        if index >= itemCount {
            let contentLength = CGFloat(itemCount) * itemLength
                + CGFloat(max(itemCount - 1, 0)) * Self.thumbnailSpacing

            return contentLength - Self.insertionIndicatorThickness / 2
        }

        return CGFloat(index) * itemLength
            + (CGFloat(index) - 0.5) * Self.thumbnailSpacing
    }

    private func updateThumbnailScreenFrame(itemID: UUID, frame: CGRect?) {
        if let frame {
            thumbnailScreenFrames[itemID] = frame
        } else {
            thumbnailScreenFrames[itemID] = nil
        }
    }

    private func updateReorderDrag(for item: ScreenshotItem, update: ScreenshotDragUpdate) {
        guard let currentIndex = store.screenshots.firstIndex(where: { $0.id == item.id }) else {
            clearReorderState()
            return
        }

        let sourceIndex = reorderDrag?.itemID == item.id ? reorderDrag?.sourceIndex ?? currentIndex : currentIndex
        let drag = ScreenshotReorderDrag(
            itemID: item.id,
            sourceIndex: sourceIndex,
            translation: axisTranslation(update.translation),
            screenPoint: update.screenPoint,
            initialFrame: initialFrame(for: item.id)
        )
        reorderDrag = drag

        let destinationIndex = reorderCalculator.destinationIndexAfterRemoval(
            drag: drag,
            orderedIDs: store.screenshots.map(\.id),
            frames: thumbnailScreenFrames
        )
        activeDropIndex = store.canMoveScreenshot(withID: item.id, toDestinationIndex: destinationIndex)
            ? reorderCalculator.visualInsertionIndex(destinationIndex: destinationIndex, sourceIndex: sourceIndex)
            : nil
    }

    private func completeReorderDrag(for item: ScreenshotItem, update: ScreenshotDragUpdate) {
        guard let currentIndex = store.screenshots.firstIndex(where: { $0.id == item.id }) else {
            clearReorderState()
            return
        }

        let sourceIndex = reorderDrag?.itemID == item.id ? reorderDrag?.sourceIndex ?? currentIndex : currentIndex
        let completedDrag = ScreenshotReorderDrag(
            itemID: item.id,
            sourceIndex: sourceIndex,
            translation: axisTranslation(update.translation),
            screenPoint: update.screenPoint,
            initialFrame: initialFrame(for: item.id)
        )
        let destinationIndex = reorderCalculator.destinationIndexAfterRemoval(
            drag: completedDrag,
            orderedIDs: store.screenshots.map(\.id),
            frames: thumbnailScreenFrames
        )

        if store.canMoveScreenshot(withID: item.id, toDestinationIndex: destinationIndex) {
            store.moveScreenshot(withID: item.id, toDestinationIndex: destinationIndex)
        }

        clearReorderState()
    }

    private func clearReorderState() {
        reorderDrag = nil
        activeDropIndex = nil
    }

    private func reorderOffset(for itemID: UUID) -> CGSize {
        guard let reorderDrag, reorderDrag.itemID == itemID else {
            return .zero
        }

        switch stackDirection {
        case .horizontal:
            return CGSize(width: reorderDrag.translation, height: 0)
        case .vertical:
            return CGSize(width: 0, height: reorderDrag.translation)
        }
    }

    private func initialFrame(for itemID: UUID) -> CGRect? {
        if reorderDrag?.itemID == itemID {
            return reorderDrag?.initialFrame
        }

        return thumbnailScreenFrames[itemID]
    }

    private var reorderCalculator: ShelfReorderCalculator {
        ShelfReorderCalculator(stackDirection: stackDirection, itemStep: itemStep)
    }

    private var itemStep: CGFloat {
        let cardSize = Self.cardSize(for: thumbnailSize)

        switch stackDirection {
        case .horizontal:
            return cardSize.width + Self.thumbnailSpacing
        case .vertical:
            return cardSize.height + Self.thumbnailSpacing
        }
    }

    private func axisTranslation(_ translation: CGSize) -> CGFloat {
        switch stackDirection {
        case .horizontal:
            return translation.width
        case .vertical:
            return translation.height
        }
    }
}

struct ScreenshotDragUpdate {
    let translation: CGSize
    let screenPoint: CGPoint?
}

private struct ScreenshotThumbnailView: View {
    let item: ScreenshotItem
    let thumbnailSize: CGSize
    let stackDirection: StackDirection
    let autoSaveEnabled: Bool
    let closeAction: () -> Void
    let closeAllAction: () -> Void
    let copyAction: () -> Void
    let copyTextAction: () -> Void
    let addToShelfAction: () -> Void
    let showInFinderAction: () -> Void
    let saveAsAction: () -> Void
    let quickSaveAction: () -> Void
    let saveExportAction: (ScreenshotExportOption) -> Void
    let pinAction: () -> Void
    let openAction: () -> Void
    let dragPasteboardWriter: () -> NSPasteboardWriting?
    let exportOptions: [ScreenshotExportOption]
    let screenFrameChanged: (UUID, CGRect?) -> Void
    let reorderChanged: (ScreenshotDragUpdate) -> Void
    let reorderEnded: (ScreenshotDragUpdate, Bool) -> Void

    @State private var isHovering = false

    private var controlsVisible: Bool {
        isHovering
    }

    var body: some View {
        ZStack {
            Image(nsImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            ThumbnailDragInteractionView(
                image: item.image,
                stackDirection: stackDirection,
                openAction: openAction,
                pasteboardWriter: dragPasteboardWriter,
                dragChanged: reorderChanged,
                dragEnded: reorderEnded
            )
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .help(Text(AppLocalization.string("Open in Preview")))

            VStack {
                HStack {
                    ThumbnailControlButton(
                        systemName: item.isPinned ? "pin.fill" : "pin",
                        help: item.isPinned ? AppLocalization.string("Unpin") : AppLocalization.string("Pin"),
                        action: pinAction
                    )

                    Spacer()

                    ThumbnailControlButton(
                        systemName: "xmark",
                        help: AppLocalization.string("Close"),
                        action: closeAction
                    )
                }

                Spacer()

                HStack {
                    ThumbnailControlButton(
                        systemName: "pencil",
                        help: AppLocalization.string("Edit in Preview"),
                        action: openAction
                    )

                    Spacer()

                    ThumbnailControlButton(
                        systemName: "doc.on.doc",
                        help: AppLocalization.string("Copy"),
                        action: copyAction
                    )
                }
            }
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .padding(9)
            .opacity(controlsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: controlsVisible)
            .allowsHitTesting(controlsVisible)

            // Keep the pinned state discoverable even while the controls are hidden.
            if item.isPinned, !isHovering {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.35), in: Circle())
                    .frame(
                        width: thumbnailSize.width,
                        height: thumbnailSize.height,
                        alignment: .topLeading
                    )
                    .padding(9)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.24), radius: 12, y: 6)
        .frame(
            width: ScreenshotShelfView.cardSize(for: thumbnailSize).width,
            height: ScreenshotShelfView.cardSize(for: thumbnailSize).height
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .background(
            ThumbnailScreenFrameReader(id: item.id, onChange: screenFrameChanged)
        )
        .contextMenu {
            Button {
                copyAction()
            } label: {
                Label(AppLocalization.string("Copy Image"), systemImage: "doc.on.doc")
            }

            Button {
                copyTextAction()
            } label: {
                Label(AppLocalization.string("Copy Text"), systemImage: "text.viewfinder")
            }

            Button {
                openAction()
            } label: {
                Label(AppLocalization.string("Edit in Preview"), systemImage: "pencil")
            }

            Divider()

            Button {
                addToShelfAction()
            } label: {
                Label(AppLocalization.string("Add to Shelf"), systemImage: "tray.and.arrow.down")
            }

            Button {
                showInFinderAction()
            } label: {
                Label(AppLocalization.string("Show in Finder"), systemImage: "folder")
            }

            Divider()

            saveMenu

            Button {
                pinAction()
            } label: {
                Label(
                    item.isPinned ? AppLocalization.string("Unpin") : AppLocalization.string("Pin"),
                    systemImage: item.isPinned ? "pin.slash" : "pin"
                )
            }

            Divider()

            Button(role: .destructive) {
                closeAction()
            } label: {
                Label(AppLocalization.string("Close"), systemImage: "xmark")
            }

            Button(role: .destructive) {
                closeAllAction()
            } label: {
                Label(AppLocalization.string("Close All"), systemImage: "trash")
            }
        }
    }

    // Save is kept distinct from the app-store "Export Named Copies" export.
    // Quick Save is redundant when auto-save already writes each capture to disk.
    @ViewBuilder
    private var saveMenu: some View {
        if autoSaveEnabled {
            Button {
                saveAsAction()
            } label: {
                Label(AppLocalization.string("Save As..."), systemImage: "square.and.arrow.down")
            }
        } else {
            Menu {
                Button {
                    quickSaveAction()
                } label: {
                    Label(AppLocalization.string("Quick Save"), systemImage: "bolt")
                }

                Button {
                    saveAsAction()
                } label: {
                    Label(AppLocalization.string("Save As..."), systemImage: "square.and.arrow.down")
                }
            } label: {
                Label(AppLocalization.string("Save"), systemImage: "square.and.arrow.down")
            }
        }

        if !exportOptions.isEmpty {
            Menu {
                ForEach(exportOptions) { option in
                    Button {
                        saveExportAction(option)
                    } label: {
                        Label(option.filename, systemImage: "square.and.arrow.down")
                    }
                }
            } label: {
                Label(AppLocalization.string("Export Named Copies"), systemImage: "square.and.arrow.up.on.square")
            }
        }

        Divider()
    }
}


private struct ShelfInsertionIndicator: View {
    let stackDirection: StackDirection

    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .shadow(color: Color.accentColor.opacity(0.5), radius: 4)
            .frame(
                width: stackDirection == .horizontal ? 4 : nil,
                height: stackDirection == .horizontal ? nil : 4
            )
    }
}

private struct ThumbnailControlButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 27, height: 27)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
