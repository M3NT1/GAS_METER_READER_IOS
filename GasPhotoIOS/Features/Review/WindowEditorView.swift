import SwiftUI
import UIKit

struct WindowEditorView: View {
    @Binding var window: NormalizedRect?
    let image: UIImage
    var isAnalyzing: Bool = false
    var onWindowChanged: ((NormalizedRect) -> Void)? = nil

    @State private var dragStartWindow: NormalizedRect? = nil
    @State private var pinchStartWindow: NormalizedRect? = nil
    @State private var activeLoupePoint: CGPoint? = nil
    @State private var loupePosition: CGPoint? = nil

    private let minWidthRatio: Double = 0.005
    private let minHeightRatio: Double = 0.0005
    private let handleTouchSize: CGFloat = 36
    private let handleVisualSize: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let fitRect = aspectFitRect(imageSize: image.size, in: proxy.size)

            ZStack {
                // 1. The photo exactly filling fitRect
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fitRect.width, height: fitRect.height)
                    .position(x: fitRect.midX, y: fitRect.midY)

                if let currentWindow = window {
                    let windowRect = rect(for: currentWindow, in: fitRect)
                    let isVeryThin = windowRect.height < 24
                    let topHandleY = isVeryThin ? windowRect.minY - 12 : windowRect.minY
                    let bottomHandleY = isVeryThin ? windowRect.maxY + 12 : windowRect.maxY

                    // 2. Dim overlay outside the active window
                    dimmedBackground(fitRect: fitRect, windowRect: windowRect)

                    // 3. The Recognition Bounding Box (Pure frame without child views constraining height)
                    ZStack {
                        // Box Fill & Border
                        RoundedRectangle(cornerRadius: min(3, max(0, windowRect.height / 2)), style: .continuous)
                            .fill(isAnalyzing ? Color.yellow.opacity(0.12) : Color.cyan.opacity(0.15))

                        RoundedRectangle(cornerRadius: min(3, max(0, windowRect.height / 2)), style: .continuous)
                            .stroke(isAnalyzing ? Color.yellow : Color.cyan, lineWidth: windowRect.height < 6 ? 1 : 2)

                        // 8-roller vertical divider tick guidelines (shown when height is adequate)
                        if windowRect.height >= 14 {
                            rollerGuideDividers(windowRect: windowRect)
                        }

                        // Scanning laser wave sweeping across rollers during re-analysis
                        if isAnalyzing {
                            LaserRollerScanner()
                                .clipShape(RoundedRectangle(cornerRadius: min(3, max(0, windowRect.height / 2)), style: .continuous))
                        }
                    }
                    .frame(width: windowRect.width, height: windowRect.height)
                    .position(x: windowRect.midX, y: windowRect.midY)
                    // Center Pan Gesture to drag the whole frame
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                handleCenterPan(gesture: gesture, fitRect: fitRect, containerSize: proxy.size)
                            }
                            .onEnded { _ in
                                finalizeDrag()
                            }
                    )
                    // Two-finger Pinch (Magnification) Gesture to shrink / expand frame
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                handlePinch(scale: scale, fitRect: fitRect, containerSize: proxy.size)
                            }
                            .onEnded { _ in
                                finalizePinch()
                            }
                    )

                    // Floating Tag Label (Positioned independently above or below frame so it never inflates box height)
                    Group {
                        let isNearTop = windowRect.minY < (fitRect.minY + 24)
                        let tagY = isNearTop ? windowRect.maxY + 16 : windowRect.minY - 14

                        HStack(spacing: 4) {
                            if isAnalyzing {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.black)
                                Text("Felismerés...")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.black)
                            } else {
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Számláló")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isAnalyzing ? Color.yellow : Color.cyan, in: Capsule())
                        .position(x: windowRect.midX, y: tagY)
                        .allowsHitTesting(false)
                    }

                    // 4. Four Edge Drag Handles (with outside offset on very thin boxes to avoid touch collisions)
                    edgeHandleHorizontal(
                        position: CGPoint(x: windowRect.midX, y: topHandleY),
                        label: "Felső él",
                        gesture: DragGesture()
                            .onChanged { g in handleTopEdge(gesture: g, fitRect: fitRect, containerSize: proxy.size) }
                            .onEnded { _ in finalizeDrag() }
                    )

                    edgeHandleHorizontal(
                        position: CGPoint(x: windowRect.midX, y: bottomHandleY),
                        label: "Alsó él",
                        gesture: DragGesture()
                            .onChanged { g in handleBottomEdge(gesture: g, fitRect: fitRect, containerSize: proxy.size) }
                            .onEnded { _ in finalizeDrag() }
                    )

                    edgeHandleVertical(
                        position: CGPoint(x: windowRect.minX, y: windowRect.midY),
                        label: "Bal él",
                        gesture: DragGesture()
                            .onChanged { g in handleLeftEdge(gesture: g, fitRect: fitRect, containerSize: proxy.size) }
                            .onEnded { _ in finalizeDrag() }
                    )

                    edgeHandleVertical(
                        position: CGPoint(x: windowRect.maxX, y: windowRect.midY),
                        label: "Jobb él",
                        gesture: DragGesture()
                            .onChanged { g in handleRightEdge(gesture: g, fitRect: fitRect, containerSize: proxy.size) }
                            .onEnded { _ in finalizeDrag() }
                    )

                    // 5. Four Corner Drag Handles
                    cornerHandle(
                        position: CGPoint(x: windowRect.minX, y: windowRect.minY),
                        label: "Bal felső sarok",
                        gesture: DragGesture()
                            .onChanged { g in handleTopLeftCorner(gesture: g, fitRect: fitRect, containerSize: proxy.size) }
                            .onEnded { _ in finalizeDrag() }
                    )

                    cornerHandle(
                        position: CGPoint(x: windowRect.maxX, y: windowRect.minY),
                        label: "Jobb felső sarok",
                        gesture: DragGesture()
                            .onChanged { g in handleTopRightCorner(gesture: g, fitRect: fitRect, containerSize: proxy.size) }
                            .onEnded { _ in finalizeDrag() }
                    )

                    cornerHandle(
                        position: CGPoint(x: windowRect.minX, y: windowRect.maxY),
                        label: "Bal alsó sarok",
                        gesture: DragGesture()
                            .onChanged { g in handleBottomLeftCorner(gesture: g, fitRect: fitRect, containerSize: proxy.size) }
                            .onEnded { _ in finalizeDrag() }
                    )

                    cornerHandle(
                        position: CGPoint(x: windowRect.maxX, y: windowRect.maxY),
                        label: "Jobb alsó sarok",
                        gesture: DragGesture()
                            .onChanged { g in handleBottomRightCorner(gesture: g, fitRect: fitRect, containerSize: proxy.size) }
                            .onEnded { _ in finalizeDrag() }
                    )

                    // 5. Floating Magnifier Loupe when dragging
                    if let target = activeLoupePoint, let pos = loupePosition {
                        MagnifierLoupeView(
                            image: image,
                            targetPoint: target,
                            fitRect: fitRect,
                            zoom: 2.5,
                            loupeDiameter: 120
                        )
                        .position(pos)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .zIndex(100)
                    }
                } else {
                    // Fallback when no frame detected
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let fallback = NormalizedRect(left: 0.15, top: 0.38, right: 0.85, bottom: 0.62)
                        window = fallback
                        onWindowChanged?(fallback)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.viewfinder")
                            Text("Keret kijelölése")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.cyan, in: Capsule())
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    }
                    .position(x: fitRect.midX, y: fitRect.midY)
                }
            }
        }
    }

    // Aspect-fit image frame calculation
    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            let y = (containerSize.height - height) / 2
            return CGRect(x: 0, y: y, width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            let x = (containerSize.width - width) / 2
            return CGRect(x: x, y: 0, width: width, height: height)
        }
    }

    private func rect(for window: NormalizedRect, in fitRect: CGRect) -> CGRect {
        CGRect(
            x: fitRect.minX + CGFloat(window.left) * fitRect.width,
            y: fitRect.minY + CGFloat(window.top) * fitRect.height,
            width: max(8, CGFloat(window.right - window.left) * fitRect.width),
            height: max(2, CGFloat(window.bottom - window.top) * fitRect.height)
        )
    }

    // Dimming mask
    @ViewBuilder
    private func dimmedBackground(fitRect: CGRect, windowRect: CGRect) -> some View {
        Color.black.opacity(0.35)
            .mask {
                Rectangle()
                    .frame(width: fitRect.width, height: fitRect.height)
                    .position(x: fitRect.midX, y: fitRect.midY)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .frame(width: windowRect.width, height: windowRect.height)
                            .position(x: windowRect.midX, y: windowRect.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }

    // 8-roller guideline dividers
    @ViewBuilder
    private func rollerGuideDividers(windowRect: CGRect) -> some View {
        Canvas { context, size in
            for i in 1..<8 {
                let x = size.width * (CGFloat(i) / 8.0)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(i == 5 ? Color.red.opacity(0.8) : Color.white.opacity(0.4)),
                    style: StrokeStyle(lineWidth: i == 5 ? 1.5 : 1, dash: [3, 2])
                )
            }
        }
        .allowsHitTesting(false)
    }

    // Corner handle component
    private func cornerHandle(
        position: CGPoint,
        label: String,
        gesture: some Gesture
    ) -> some View {
        ZStack {
            // Invisible larger touch target
            Color.clear
                .frame(width: handleTouchSize, height: handleTouchSize)
                .contentShape(Rectangle())

            // Visible circle handle
            Circle()
                .fill(Color.white)
                .frame(width: handleVisualSize, height: handleVisualSize)
                .overlay(Circle().stroke(Color.cyan, lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
        }
        .position(position)
        .gesture(gesture)
        .accessibilityLabel(label)
    }

    // Horizontal edge handle (Top and Bottom)
    private func edgeHandleHorizontal(
        position: CGPoint,
        label: String,
        gesture: some Gesture
    ) -> some View {
        ZStack {
            Color.clear
                .frame(width: 60, height: 32)
                .contentShape(Rectangle())

            Capsule()
                .fill(Color.white)
                .frame(width: 24, height: 5)
                .overlay(Capsule().stroke(Color.cyan, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        }
        .position(position)
        .gesture(gesture)
        .accessibilityLabel(label)
    }

    // Vertical edge handle (Left and Right)
    private func edgeHandleVertical(
        position: CGPoint,
        label: String,
        gesture: some Gesture
    ) -> some View {
        ZStack {
            Color.clear
                .frame(width: 32, height: 50)
                .contentShape(Rectangle())

            Capsule()
                .fill(Color.white)
                .frame(width: 5, height: 20)
                .overlay(Capsule().stroke(Color.cyan, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        }
        .position(position)
        .gesture(gesture)
        .accessibilityLabel(label)
    }

    // Drag handlers
    private func updateLoupe(target: CGPoint, touchPoint: CGPoint, in containerSize: CGSize) {
        activeLoupePoint = target
        let loupeRadius: CGFloat = 60
        let clampedX = min(max(touchPoint.x, loupeRadius + 12), containerSize.width - loupeRadius - 12)
        let yOffset: CGFloat = touchPoint.y < 120 ? 95 : -95
        let clampedY = min(max(touchPoint.y + yOffset, loupeRadius + 8), containerSize.height - loupeRadius - 8)
        loupePosition = CGPoint(x: clampedX, y: clampedY)
    }

    private func handlePinch(scale: CGFloat, fitRect: CGRect, containerSize: CGSize) {
        if pinchStartWindow == nil { pinchStartWindow = window }
        guard let start = pinchStartWindow, fitRect.width > 0, fitRect.height > 0 else { return }

        let scaled = start.scaled(by: Double(scale), minWidth: minWidthRatio, minHeight: minHeightRatio)
        window = scaled

        let centerTarget = CGPoint(
            x: fitRect.minX + CGFloat(scaled.centerX) * fitRect.width,
            y: fitRect.minY + CGFloat(scaled.centerY) * fitRect.height
        )
        updateLoupe(target: centerTarget, touchPoint: centerTarget, in: containerSize)
    }

    private func finalizePinch() {
        pinchStartWindow = nil
        finalizeDrag()
    }

    private func handleCenterPan(gesture: DragGesture.Value, fitRect: CGRect, containerSize: CGSize) {
        if pinchStartWindow != nil { return }
        if dragStartWindow == nil { dragStartWindow = window }
        guard let start = dragStartWindow, fitRect.width > 0, fitRect.height > 0 else { return }

        let width = start.right - start.left
        let height = start.bottom - start.top
        let deltaX = Double(gesture.translation.width / fitRect.width)
        let deltaY = Double(gesture.translation.height / fitRect.height)

        var newLeft = start.left + deltaX
        var newTop = start.top + deltaY

        newLeft = min(max(0.0, newLeft), 1.0 - width)
        newTop = min(max(0.0, newTop), 1.0 - height)

        let newWindow = NormalizedRect(
            left: newLeft,
            top: newTop,
            right: newLeft + width,
            bottom: newTop + height
        )
        window = newWindow

        let centerTarget = CGPoint(
            x: fitRect.minX + CGFloat(newLeft + width / 2.0) * fitRect.width,
            y: fitRect.minY + CGFloat(newTop + height / 2.0) * fitRect.height
        )
        updateLoupe(target: centerTarget, touchPoint: gesture.location, in: containerSize)
    }

    // Edge Drag Handlers
    private func handleTopEdge(gesture: DragGesture.Value, fitRect: CGRect, containerSize: CGSize) {
        if dragStartWindow == nil { dragStartWindow = window }
        guard let start = dragStartWindow, fitRect.height > 0 else { return }

        let deltaY = Double(gesture.translation.height / fitRect.height)
        let newTop = min(max(0.0, start.top + deltaY), start.bottom - minHeightRatio)

        window = NormalizedRect(left: start.left, top: newTop, right: start.right, bottom: start.bottom)

        let target = CGPoint(
            x: fitRect.minX + CGFloat(start.centerX) * fitRect.width,
            y: fitRect.minY + CGFloat(newTop) * fitRect.height
        )
        updateLoupe(target: target, touchPoint: gesture.location, in: containerSize)
    }

    private func handleBottomEdge(gesture: DragGesture.Value, fitRect: CGRect, containerSize: CGSize) {
        if dragStartWindow == nil { dragStartWindow = window }
        guard let start = dragStartWindow, fitRect.height > 0 else { return }

        let deltaY = Double(gesture.translation.height / fitRect.height)
        let newBottom = max(min(1.0, start.bottom + deltaY), start.top + minHeightRatio)

        window = NormalizedRect(left: start.left, top: start.top, right: start.right, bottom: newBottom)

        let target = CGPoint(
            x: fitRect.minX + CGFloat(start.centerX) * fitRect.width,
            y: fitRect.minY + CGFloat(newBottom) * fitRect.height
        )
        updateLoupe(target: target, touchPoint: gesture.location, in: containerSize)
    }

    private func handleLeftEdge(gesture: DragGesture.Value, fitRect: CGRect, containerSize: CGSize) {
        if dragStartWindow == nil { dragStartWindow = window }
        guard let start = dragStartWindow, fitRect.width > 0 else { return }

        let deltaX = Double(gesture.translation.width / fitRect.width)
        let newLeft = min(max(0.0, start.left + deltaX), start.right - minWidthRatio)

        window = NormalizedRect(left: newLeft, top: start.top, right: start.right, bottom: start.bottom)

        let target = CGPoint(
            x: fitRect.minX + CGFloat(newLeft) * fitRect.width,
            y: fitRect.minY + CGFloat(start.centerY) * fitRect.height
        )
        updateLoupe(target: target, touchPoint: gesture.location, in: containerSize)
    }

    private func handleRightEdge(gesture: DragGesture.Value, fitRect: CGRect, containerSize: CGSize) {
        if dragStartWindow == nil { dragStartWindow = window }
        guard let start = dragStartWindow, fitRect.width > 0 else { return }

        let deltaX = Double(gesture.translation.width / fitRect.width)
        let newRight = max(min(1.0, start.right + deltaX), start.left + minWidthRatio)

        window = NormalizedRect(left: start.left, top: start.top, right: newRight, bottom: start.bottom)

        let target = CGPoint(
            x: fitRect.minX + CGFloat(newRight) * fitRect.width,
            y: fitRect.minY + CGFloat(start.centerY) * fitRect.height
        )
        updateLoupe(target: target, touchPoint: gesture.location, in: containerSize)
    }

    // Corner Drag Handlers
    private func handleTopLeftCorner(gesture: DragGesture.Value, fitRect: CGRect, containerSize: CGSize) {
        if dragStartWindow == nil { dragStartWindow = window }
        guard let start = dragStartWindow, fitRect.width > 0, fitRect.height > 0 else { return }

        let deltaX = Double(gesture.translation.width / fitRect.width)
        let deltaY = Double(gesture.translation.height / fitRect.height)

        let newLeft = min(max(0.0, start.left + deltaX), start.right - minWidthRatio)
        let newTop = min(max(0.0, start.top + deltaY), start.bottom - minHeightRatio)

        window = NormalizedRect(left: newLeft, top: newTop, right: start.right, bottom: start.bottom)

        let cornerTarget = CGPoint(
            x: fitRect.minX + CGFloat(newLeft) * fitRect.width,
            y: fitRect.minY + CGFloat(newTop) * fitRect.height
        )
        updateLoupe(target: cornerTarget, touchPoint: gesture.location, in: containerSize)
    }

    private func handleTopRightCorner(gesture: DragGesture.Value, fitRect: CGRect, containerSize: CGSize) {
        if dragStartWindow == nil { dragStartWindow = window }
        guard let start = dragStartWindow, fitRect.width > 0, fitRect.height > 0 else { return }

        let deltaX = Double(gesture.translation.width / fitRect.width)
        let deltaY = Double(gesture.translation.height / fitRect.height)

        let newRight = max(min(1.0, start.right + deltaX), start.left + minWidthRatio)
        let newTop = min(max(0.0, start.top + deltaY), start.bottom - minHeightRatio)

        window = NormalizedRect(left: start.left, top: newTop, right: newRight, bottom: start.bottom)

        let cornerTarget = CGPoint(
            x: fitRect.minX + CGFloat(newRight) * fitRect.width,
            y: fitRect.minY + CGFloat(newTop) * fitRect.height
        )
        updateLoupe(target: cornerTarget, touchPoint: gesture.location, in: containerSize)
    }

    private func handleBottomLeftCorner(gesture: DragGesture.Value, fitRect: CGRect, containerSize: CGSize) {
        if dragStartWindow == nil { dragStartWindow = window }
        guard let start = dragStartWindow, fitRect.width > 0, fitRect.height > 0 else { return }

        let deltaX = Double(gesture.translation.width / fitRect.width)
        let deltaY = Double(gesture.translation.height / fitRect.height)

        let newLeft = min(max(0.0, start.left + deltaX), start.right - minWidthRatio)
        let newBottom = max(min(1.0, start.bottom + deltaY), start.top + minHeightRatio)

        window = NormalizedRect(left: newLeft, top: start.top, right: start.right, bottom: newBottom)

        let cornerTarget = CGPoint(
            x: fitRect.minX + CGFloat(newLeft) * fitRect.width,
            y: fitRect.minY + CGFloat(newBottom) * fitRect.height
        )
        updateLoupe(target: cornerTarget, touchPoint: gesture.location, in: containerSize)
    }

    private func handleBottomRightCorner(gesture: DragGesture.Value, fitRect: CGRect, containerSize: CGSize) {
        if dragStartWindow == nil { dragStartWindow = window }
        guard let start = dragStartWindow, fitRect.width > 0, fitRect.height > 0 else { return }

        let deltaX = Double(gesture.translation.width / fitRect.width)
        let deltaY = Double(gesture.translation.height / fitRect.height)

        let newRight = max(min(1.0, start.right + deltaX), start.left + minWidthRatio)
        let newBottom = max(min(1.0, start.bottom + deltaY), start.top + minHeightRatio)

        window = NormalizedRect(left: start.left, top: start.top, right: newRight, bottom: newBottom)

        let cornerTarget = CGPoint(
            x: fitRect.minX + CGFloat(newRight) * fitRect.width,
            y: fitRect.minY + CGFloat(newBottom) * fitRect.height
        )
        updateLoupe(target: cornerTarget, touchPoint: gesture.location, in: containerSize)
    }

    private func finalizeDrag() {
        dragStartWindow = nil
        withAnimation(.easeOut(duration: 0.15)) {
            activeLoupePoint = nil
            loupePosition = nil
        }
        if let finalWindow = window {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onWindowChanged?(finalWindow)
        }
    }
}

// Laser wave animation across roller digits when analyzing/re-evaluating
private struct LaserRollerScanner: View {
    @State private var scanX: CGFloat = 0.0

    var body: some View {
        GeometryReader { geo in
            let beamX = scanX * geo.size.width

            ZStack(alignment: .center) {
                // Soft gradient trail
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.yellow.opacity(0.0),
                                Color.yellow.opacity(0.35),
                                Color.white.opacity(0.5),
                                Color.yellow.opacity(0.35),
                                Color.yellow.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 28, height: geo.size.height)

                // Laser core
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: geo.size.height)
                    .shadow(color: Color.yellow, radius: 4, x: 0, y: 0)
            }
            .position(x: beamX, y: geo.size.height / 2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                scanX = 1.0
            }
        }
    }
}
