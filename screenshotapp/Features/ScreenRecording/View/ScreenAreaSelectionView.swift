import SwiftUI

struct ScreenAreaSelectionView: View {
    private static let minimumSize = CGSize(width: 160, height: 100)

    let initialRect: CGRect?
    let onComplete: (CGRect?) -> Void

    @State private var selectionRect: CGRect?
    @State private var gestureStartRect: CGRect?
    @State private var drawingStartPoint: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)

            ZStack(alignment: .topLeading) {
                shade(in: bounds)
                    .contentShape(Rectangle())
                    .gesture(drawSelectionGesture(in: bounds))

                if let selectionRect {
                    selection(in: selectionRect, bounds: bounds)
                }

                VStack(spacing: 5) {
                    Text(AppLocalization.string("Select Recording Area"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(AppLocalization.string("Drag to draw, then move or resize the selection."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(.ultraThickMaterial, in: Capsule())
                .position(x: bounds.midX, y: 42)

                controls
                    .position(x: bounds.midX, y: bounds.maxY - 52)
            }
            .onAppear {
                if selectionRect == nil {
                    selectionRect = initialRect.map { clamp($0, to: bounds) }
                        ?? centeredInitialRect(in: bounds)
                }
            }
        }
        .ignoresSafeArea()
        .onExitCommand { onComplete(nil) }
    }

    private func shade(in bounds: CGRect) -> some View {
        Path { path in
            path.addRect(bounds)
            if let selectionRect {
                path.addRoundedRect(
                    in: selectionRect,
                    cornerSize: CGSize(width: 8, height: 8)
                )
            }
        }
        .fill(.black.opacity(0.48), style: FillStyle(eoFill: true))
    }

    private func selection(in rect: CGRect, bounds: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Color.white.opacity(0.001)
                .frame(width: rect.width, height: rect.height)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 3)
                }
                .position(x: rect.midX, y: rect.midY)
                .gesture(moveGesture(in: bounds))

            Text("\(Int(rect.width)) × \(Int(rect.height))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.66), in: Capsule())
                .position(x: rect.midX, y: max(rect.minY - 18, 80))

            ForEach(SelectionHandle.allCases) { handle in
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                    .frame(width: 13, height: 13)
                    .position(handle.position(in: rect))
                    .gesture(resizeGesture(handle: handle, in: bounds))
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(AppLocalization.string("Cancel")) {
                onComplete(nil)
            }
            .keyboardShortcut(.cancelAction)

            Button(AppLocalization.string("Use Selection")) {
                onComplete(selectionRect)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selectionRect == nil)
        }
        .padding(10)
        .background(.ultraThickMaterial, in: Capsule())
    }

    private func drawSelectionGesture(in bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = drawingStartPoint ?? value.startLocation
                drawingStartPoint = start
                let rect = CGRect(
                    x: min(start.x, value.location.x),
                    y: min(start.y, value.location.y),
                    width: abs(value.location.x - start.x),
                    height: abs(value.location.y - start.y)
                )
                selectionRect = clamp(rect, to: bounds, enforcingMinimum: false)
            }
            .onEnded { _ in
                drawingStartPoint = nil
                if let selectionRect {
                    self.selectionRect = clamp(selectionRect, to: bounds)
                }
            }
    }

    private func moveGesture(in bounds: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = gestureStartRect ?? selectionRect
                gestureStartRect = start
                guard var rect = start else { return }
                rect.origin.x += value.translation.width
                rect.origin.y += value.translation.height
                selectionRect = clamp(rect, to: bounds)
            }
            .onEnded { _ in gestureStartRect = nil }
    }

    private func resizeGesture(handle: SelectionHandle, in bounds: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = gestureStartRect ?? selectionRect
                gestureStartRect = start
                guard let start else { return }
                selectionRect = resized(
                    start,
                    handle: handle,
                    translation: value.translation,
                    bounds: bounds
                )
            }
            .onEnded { _ in gestureStartRect = nil }
    }

    private func resized(
        _ rect: CGRect,
        handle: SelectionHandle,
        translation: CGSize,
        bounds: CGRect
    ) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        if handle.movesLeft { minX += translation.width }
        if handle.movesRight { maxX += translation.width }
        if handle.movesTop { minY += translation.height }
        if handle.movesBottom { maxY += translation.height }

        if maxX - minX < Self.minimumSize.width {
            if handle.movesLeft { minX = maxX - Self.minimumSize.width }
            if handle.movesRight { maxX = minX + Self.minimumSize.width }
        }
        if maxY - minY < Self.minimumSize.height {
            if handle.movesTop { minY = maxY - Self.minimumSize.height }
            if handle.movesBottom { maxY = minY + Self.minimumSize.height }
        }

        return clamp(
            CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            to: bounds
        )
    }

    private func centeredInitialRect(in bounds: CGRect) -> CGRect {
        let width = max(bounds.width * 0.62, Self.minimumSize.width)
        let height = max(bounds.height * 0.58, Self.minimumSize.height)
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: min(width, bounds.width),
            height: min(height, bounds.height)
        )
    }

    private func clamp(
        _ rect: CGRect,
        to bounds: CGRect,
        enforcingMinimum: Bool = true
    ) -> CGRect {
        let minimumWidth = enforcingMinimum ? Self.minimumSize.width : 1
        let minimumHeight = enforcingMinimum ? Self.minimumSize.height : 1
        let width = min(max(rect.width, minimumWidth), bounds.width)
        let height = min(max(rect.height, minimumHeight), bounds.height)
        return CGRect(
            x: min(max(rect.minX, bounds.minX), bounds.maxX - width),
            y: min(max(rect.minY, bounds.minY), bounds.maxY - height),
            width: width,
            height: height
        )
    }
}

private enum SelectionHandle: CaseIterable, Identifiable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var id: Self { self }
    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}
