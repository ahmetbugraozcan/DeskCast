import SwiftUI

// MARK: - Launcher

/// The panel grid. Drag a tile to reorder; Edit (or a tile's context menu)
/// shows remove badges and, after the shown panels, the hidden ones to add back.
struct IslandLauncherView: View {
    @ObservedObject var store: DynamicIslandViewModel

    @State private var isEditing = false
    /// Order while a drag is in flight; saved when the drag ends.
    @State private var draftOrder: [IslandPanel]?
    @State private var drag: TileDrag?
    @State private var gridWidth: CGFloat = 0

    // Six columns keep three rows for up to 18 panels; more scroll.
    private static let columnCount = 6
    private static let spacing: CGFloat = 8
    private static let tileHeight: CGFloat = 72
    private static let gridSpace = "launcherGrid"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)

    private var order: [IslandPanel] {
        draftOrder ?? store.preferences.visiblePanels
    }

    private var hiddenPanels: [IslandPanel] {
        store.preferences.panelOrder.filter(store.preferences.hiddenPanels.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView {
                visibleGrid
                    .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .islandScrollFade()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isEditing)
        .onDisappear {
            isEditing = false
            draftOrder = nil
            drag = nil
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            IslandIconButton(
                systemImage: "chevron.left",
                help: AppLocalization.string("island.back"),
                action: { store.showLauncher() }
            )

            Text(AppLocalization.string("island.launcher.title"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            if isEditing {
                IslandChipButton(title: AppLocalization.string("island.launcher.done"), systemImage: "checkmark", isOn: true) {
                    isEditing = false
                }
            } else {
                IslandIconButton(
                    systemImage: "slider.horizontal.3",
                    help: AppLocalization.string("island.launcher.edit"),
                    action: { isEditing = true }
                )
            }

            IslandIconButton(
                systemImage: store.isPinned ? "pin.fill" : "pin",
                help: AppLocalization.string(store.isPinned ? "island.unpin" : "island.pin"),
                action: { store.togglePin() }
            )
        }
        .frame(height: 26)
    }

    private var visibleGrid: some View {
        LazyVGrid(columns: columns, spacing: Self.spacing) {
            ForEach(Array(order.enumerated()), id: \.element) { index, panel in
                visibleTile(panel, index: index)
            }

            if isEditing {
                // Hidden panels follow the shown ones, dimmed, ready to add back.
                ForEach(hiddenPanels) { panel in
                    LauncherTile(
                        panel: panel,
                        style: .hidden,
                        showsShortcut: false,
                        badge: .add,
                        onTap: { setHidden(panel, false) },
                        onBadge: { setHidden(panel, false) }
                    )
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            } else if !hiddenPanels.isEmpty {
                AddPanelTile { isEditing = true }
            }
        }
        .coordinateSpace(.named(Self.gridSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    private func visibleTile(_ panel: IslandPanel, index: Int) -> some View {
        let isDragging = drag?.panel == panel

        return LauncherTile(
            panel: panel,
            style: .visible(isSelected: !isEditing && store.lastSelectedPanel == panel),
            showsShortcut: store.preferences.panelShortcutsEnabled,
            badge: isEditing && order.count > 1 ? .remove : nil,
            onTap: { if !isEditing { store.select(panel) } },
            onBadge: { setHidden(panel, true) }
        )
        .contextMenu {
            Button(AppLocalization.string("island.launcher.edit")) { isEditing = true }
            if order.count > 1 {
                Button(AppLocalization.string("island.launcher.hide")) { setHidden(panel, true) }
            }
        }
        .scaleEffect(isDragging ? 1.08 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.5 : 0), radius: 10, y: 4)
        .offset(isDragging ? dragOffset(for: index) : .zero)
        .zIndex(isDragging ? 1 : 0)
        .gesture(reorderGesture(for: panel, index: index))
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    // MARK: - Editing

    private func setHidden(_ panel: IslandPanel, _ hide: Bool) {
        var hidden = store.preferences.hiddenPanels
        var visible = order
        if hide {
            hidden.insert(panel)
        } else {
            hidden.remove(panel)
            visible.append(panel)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            store.updatePanelLayout(visibleOrder: visible, hidden: hidden)
        }
    }

    // MARK: - Drag to reorder

    private struct TileDrag: Equatable {
        let panel: IslandPanel
        /// Pointer position relative to the tile's center when the drag began.
        let grabOffset: CGSize
        var location: CGPoint
    }

    private var slotSize: CGSize {
        let count = CGFloat(Self.columnCount)
        let width = max(0, (gridWidth - Self.spacing * (count - 1)) / count)
        return CGSize(width: width, height: Self.tileHeight)
    }

    private func slotCenter(_ index: Int) -> CGPoint {
        let column = CGFloat(index % Self.columnCount)
        let row = CGFloat(index / Self.columnCount)
        return CGPoint(
            x: column * (slotSize.width + Self.spacing) + slotSize.width / 2,
            y: row * (slotSize.height + Self.spacing) + slotSize.height / 2
        )
    }

    private func slotIndex(at point: CGPoint, count: Int) -> Int {
        let column = min(max(Int(point.x / (slotSize.width + Self.spacing)), 0), Self.columnCount - 1)
        let row = max(Int(point.y / (slotSize.height + Self.spacing)), 0)
        return min(row * Self.columnCount + column, count - 1)
    }

    private func dragOffset(for index: Int) -> CGSize {
        guard let drag else { return .zero }
        let center = slotCenter(index)
        return CGSize(
            width: drag.location.x - drag.grabOffset.width - center.x,
            height: drag.location.y - drag.grabOffset.height - center.y
        )
    }

    private func reorderGesture(for panel: IslandPanel, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.gridSpace))
            .onChanged { value in
                if drag?.panel != panel {
                    let center = slotCenter(index)
                    drag = TileDrag(
                        panel: panel,
                        grabOffset: CGSize(width: value.startLocation.x - center.x, height: value.startLocation.y - center.y),
                        location: value.location
                    )
                    draftOrder = order
                }
                drag?.location = value.location

                guard var current = draftOrder, let from = current.firstIndex(of: panel) else { return }
                let target = slotIndex(at: value.location, count: current.count)
                guard target != from else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    current.move(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
                    draftOrder = current
                }
            }
            .onEnded { _ in
                if let draftOrder, draftOrder != store.preferences.visiblePanels {
                    store.updatePanelLayout(visibleOrder: draftOrder, hidden: store.preferences.hiddenPanels)
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    drag = nil
                    draftOrder = nil
                }
            }
    }
}

// MARK: - Tiles

private struct LauncherTile: View {
    enum Style: Equatable {
        case visible(isSelected: Bool)
        case hidden
    }

    enum Badge {
        case remove, add
    }

    let panel: IslandPanel
    let style: Style
    let showsShortcut: Bool
    let badge: Badge?
    let onTap: () -> Void
    let onBadge: () -> Void

    @State private var isHovered = false

    private var isSelected: Bool {
        style == .visible(isSelected: true)
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: panel.systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(panel.tint ?? .white)
                .frame(height: 24)

            Text(AppLocalization.string(panel.titleKey))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)

            if showsShortcut, let label = panel.shortcutLabel {
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(IslandPalette.tertiaryText)
            }
        }
        .opacity(style == .hidden ? 0.55 : 1)
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected || isHovered ? Color(white: 0.17) : IslandPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? Color.white.opacity(0.35) : IslandPalette.cardStroke,
                    style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: style == .hidden ? [4, 3] : [])
                )
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(6)
            }
        }
        .overlay(alignment: .topLeading) {
            if let badge {
                badgeButton(badge)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onTap)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(AppLocalization.string(style == .hidden ? "island.launcher.add" : "island.launcher.hide"))) {
            onBadge()
        }
    }

    private func badgeButton(_ badge: Badge) -> some View {
        Button(action: onBadge) {
            Image(systemName: badge == .remove ? "minus" : "plus")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(badge == .remove ? Color(white: 0.32) : IslandPalette.accent.opacity(0.85)))
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(5)
        .help(AppLocalization.string(badge == .remove ? "island.launcher.hide" : "island.launcher.add"))
        .transition(.scale.combined(with: .opacity))
    }
}

/// Dashed "+" tile after the grid while some panels are hidden.
private struct AddPanelTile: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 24)
                Text(AppLocalization.string("island.launcher.add"))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isHovered ? .white : IslandPalette.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.3 : 0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(IslandScaleButtonStyle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
