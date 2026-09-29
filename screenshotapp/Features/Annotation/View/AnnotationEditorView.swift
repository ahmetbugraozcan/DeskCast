import AppKit
import SwiftUI

struct AnnotationEditorActions {
    let cancel: () -> Void
    let copy: () -> Void
    let done: () -> Void
}

/// Toolbar + fitted canvas. Drags draw with the selected tool; the Text tool
/// places an inline field that commits on Return or the next click.
struct AnnotationEditorView: View {
    @ObservedObject var model: AnnotationEditorViewModel
    let actions: AnnotationEditorActions

    @FocusState private var isTextFieldFocused: Bool
    @State private var isDrawing = false

    static let toolbarHeight: CGFloat = 52
    private static let canvasPadding: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .frame(height: Self.toolbarHeight)
                .padding(.horizontal, 12)
                .background(.bar)
            Divider()
            GeometryReader { proxy in
                let scale = fitScale(in: proxy.size)
                canvas(scale: scale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases) { tool in
                    toolButton(tool)
                }
            }
            .padding(3)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            HStack(spacing: 6) {
                ForEach(AnnotationColor.allCases) { color in
                    colorSwatch(color)
                }
            }

            HStack(spacing: 2) {
                ForEach(AnnotationSize.allCases) { size in
                    sizeButton(size)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                iconButton("arrow.uturn.backward", help: "annotate.undo", enabled: model.canUndo, action: model.undo)
                    .keyboardShortcut("z", modifiers: .command)
                iconButton("arrow.uturn.forward", help: "annotate.redo", enabled: model.canRedo, action: model.redo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                iconButton("trash", help: "annotate.clear", enabled: !model.annotations.isEmpty, action: model.clearAll)
            }

            // No Esc shortcut: Esc cancels the text being typed, never the whole edit.
            HStack(spacing: 8) {
                Button(AppLocalization.string("Cancel"), action: actions.cancel)
                Button(AppLocalization.string("Copy"), action: actions.copy)
                Button(AppLocalization.string("annotate.done"), action: actions.done)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .fixedSize()
        }
        .controlSize(.regular)
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button {
            model.tool = tool
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 26)
                .foregroundStyle(model.tool == tool ? Color.white : Color.primary)
                .background(
                    model.tool == tool ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(AppLocalization.string(tool.titleKey))
        .accessibilityLabel(AppLocalization.string(tool.titleKey))
    }

    private func colorSwatch(_ color: AnnotationColor) -> some View {
        Button {
            model.color = color
        } label: {
            Circle()
                .fill(Color(color))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                .padding(3)
                .overlay(
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                        .opacity(model.color == color ? 1 : 0)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(AppLocalization.string("annotate.color.\(color.rawValue)"))
        .accessibilityLabel(AppLocalization.string("annotate.color.\(color.rawValue)"))
    }

    private func sizeButton(_ size: AnnotationSize) -> some View {
        Button {
            model.size = size
        } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: 12 * size.symbolScale, height: 12 * size.symbolScale)
                .frame(width: 26, height: 26)
                .background(
                    model.size == size ? Color.primary.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(AppLocalization.string("annotate.size.\(size.rawValue)"))
        .accessibilityLabel(AppLocalization.string("annotate.size.\(size.rawValue)"))
    }

    private func iconButton(_ systemName: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(AppLocalization.string(help))
    }

    // MARK: - Canvas

    private func fitScale(in available: CGSize) -> CGFloat {
        let size = model.imageSize
        guard size.width > 0, size.height > 0 else { return 1 }
        let width = max(available.width - Self.canvasPadding * 2, 40)
        let height = max(available.height - Self.canvasPadding * 2, 40)
        // Never enlarge past 100 %: captures are already at screen resolution.
        return min(width / size.width, height / size.height, 1)
    }

    private func canvas(scale: CGFloat) -> some View {
        AnnotationCanvas(
            image: model.image,
            mosaic: model.mosaic,
            annotations: model.visibleAnnotations,
            scale: scale
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .overlay(alignment: .topLeading) {
            textField(scale: scale)
        }
        .contentShape(Rectangle())
        .gesture(drawingGesture(scale: scale))
        .pointerStyle(model.tool == .text ? .horizontalText : .rectSelection)
    }

    private func drawingGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isDrawing {
                    isDrawing = true
                    model.beginStroke(at: CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale))
                }
                model.continueStroke(to: CGPoint(x: value.location.x / scale, y: value.location.y / scale))
            }
            .onEnded { _ in
                isDrawing = false
                model.endStroke()
            }
    }

    @ViewBuilder
    private func textField(scale: CGFloat) -> some View {
        if let draft = model.textDraft {
            TextField(
                "",
                text: Binding(get: { model.textDraft?.text ?? "" }, set: { model.updateText($0) }),
                prompt: Text(AppLocalization.string("annotate.text.placeholder"))
            )
            .textFieldStyle(.plain)
            .font(.system(size: draft.size.fontSize * scale, weight: .bold))
            .foregroundStyle(Color(draft.color))
            .frame(minWidth: 80, alignment: .leading)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.12))
            .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .fixedSize()
            .focused($isTextFieldFocused)
            .onSubmit { model.commitText() }
            .onExitCommand { model.cancelText() }
            // Focus once the field exists; setting it in the same update is ignored.
            .onAppear { DispatchQueue.main.async { isTextFieldFocused = true } }
            .padding(.leading, draft.start.x * scale)
            .padding(.top, draft.start.y * scale)
        }
    }
}
