import SwiftUI

/// Settings → Dynamic Island → side buttons: a small picture of the island
/// with its round buttons. Click a button to move or remove it, or a dashed
/// "+" to add one (any panel, the launcher or Settings).
struct IslandSideButtonsEditor: View {
    @State private var layout = DynamicIslandSettings.sideButtons()
    @State private var selection: IslandOrbItem?

    private static let orbSize: CGFloat = 34
    private static let gap: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("island.orb.hint"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 14) {
                column(.left)
                VStack(spacing: 10) {
                    islandPicture
                    row(.bottom)
                }
                column(.right)
            }
            .frame(maxWidth: .infinity)

            controls
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        // The island's own "Remove" menu edits the same layout.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let stored = DynamicIslandSettings.sideButtons()
            if stored != layout {
                layout = stored
                if let selection, !stored.allItems.contains(selection) { self.selection = nil }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: layout)
    }

    private var islandPicture: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black)
            .overlay(
                Text(AppLocalization.string("island.orb.island"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            )
            .frame(width: 210, height: Self.orbSize * 4 + Self.gap * 3)
    }

    private func column(_ side: IslandOrbSide) -> some View {
        VStack(spacing: Self.gap) {
            ForEach(layout[side], id: \.self, content: orb)
            addButton(side)
        }
        .frame(width: Self.orbSize)
    }

    private func row(_ side: IslandOrbSide) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(layout[side], id: \.self, content: orb)
            addButton(side)
        }
        .frame(height: Self.orbSize)
    }

    private func orb(_ item: IslandOrbItem) -> some View {
        let isSelected = selection == item
        return Button {
            selection = isSelected ? nil : item
        } label: {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.orbSize, height: Self.orbSize)
                .background(Circle().fill(Color.black))
                .overlay(Circle().stroke(isSelected ? Color.accentColor : Color.white.opacity(0.12), lineWidth: isSelected ? 2.5 : 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(AppLocalization.string(item.titleKey))
    }

    @ViewBuilder
    private func addButton(_ side: IslandOrbSide) -> some View {
        if layout.canAdd(to: side) {
            Menu {
                ForEach(layout.unusedItems, id: \.self) { item in
                    Button {
                        layout.add(item, to: side)
                        selection = item
                        save()
                    } label: {
                        Label(AppLocalization.string(item.titleKey), systemImage: item.systemImage)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.orbSize, height: Self.orbSize)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])))
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: Self.orbSize, height: Self.orbSize)
            .help(AppLocalization.formatted("island.orb.add", AppLocalization.string(side.titleKey)))
        }
    }

    // MARK: Selected button

    private var controls: some View {
        HStack(spacing: 8) {
            if let selection, let side = IslandOrbSide.allCases.first(where: { layout[$0].contains(selection) }) {
                Label(AppLocalization.string(selection.titleKey), systemImage: selection.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    layout.move(selection, by: -1)
                    save()
                } label: {
                    Image(systemName: side == .bottom ? "arrow.left" : "arrow.up")
                }
                .disabled(layout[side].first == selection)

                Button {
                    layout.move(selection, by: 1)
                    save()
                } label: {
                    Image(systemName: side == .bottom ? "arrow.right" : "arrow.down")
                }
                .disabled(layout[side].last == selection)

                Menu(AppLocalization.string("island.orb.moveTo")) {
                    ForEach(IslandOrbSide.allCases.filter { $0 != side }, id: \.self) { target in
                        Button(AppLocalization.string(target.titleKey)) {
                            layout.add(selection, to: target)
                            save()
                        }
                        .disabled(layout[target].count >= IslandOrbLayout.maxPerSide)
                    }
                }
                .fixedSize()

                Button(AppLocalization.string("island.orb.remove"), role: .destructive) {
                    layout.remove(selection)
                    self.selection = nil
                    save()
                }
            } else {
                Text(AppLocalization.string("island.orb.selectHint"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(AppLocalization.string("island.orb.reset")) {
                    layout = .standard
                    save()
                }
                .disabled(layout == .standard)
            }
        }
        .frame(height: 26)
    }

    private func save() {
        DynamicIslandSettings.setSideButtons(layout)
    }
}
