@preconcurrency import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct CaptureView: View {
    @Bindable var model: CaptureViewModel
    var credentialStore: (any CredentialStore)? = nil

    @State private var isShowingSettings = false
    @State private var isShowingHistory = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isShutterPressed = false
    @State private var isShutterFlashing = false
    @State private var focusVisualPoint: CGPoint? = nil
    @State private var isFocusAnimating = false
    @State private var currentBaseZoom: CGFloat = 1.0
    @State private var focusDismissTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            // 1. Full-screen Camera Viewfinder
            CameraPreview(session: model.session, onTap: handleTapToFocus)
                .ignoresSafeArea()
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let target = currentBaseZoom * value
                            model.setZoom(factor: target)
                        }
                        .onEnded { _ in
                            currentBaseZoom = model.zoomFactor
                        }
                )

            #if targetEnvironment(simulator)
            Color(white: 0.12)
                .ignoresSafeArea()
            #endif

            // Freeze-frame snapshot of captured photo during recognition
            if model.isCapturing, let previewImg = model.capturedPreviewImage {
                Image(uiImage: previewImg)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.18))
                    .transition(.opacity)
            }

            // Shutter Flash Effect
            Color.white
                .ignoresSafeArea()
                .opacity(isShutterFlashing ? 0.75 : 0.0)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.2), value: isShutterFlashing)

            // 2. Unified Vignette Mask and Concentric Reticle Frame
            GeometryReader { proxy in
                let boxWidth: CGFloat = min(proxy.size.width - 48, 330)
                let boxHeight: CGFloat = 130
                let boxCenter = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2 - 30)

                ZStack {
                    // Dimmed Vignette Mask
                    Color.black.opacity(model.isCapturing ? 0.55 : 0.45)
                        .mask {
                            Rectangle()
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .frame(width: boxWidth, height: boxHeight)
                                        .position(boxCenter)
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                        }

                    // Concentric Target Reticle Frame with Apple Intelligence Glow & Scanning Wave
                    ScanningReticleOverlay(
                        isScanning: model.isCapturing,
                        phase: model.phase,
                        boxWidth: boxWidth,
                        boxHeight: boxHeight,
                        boxCenter: boxCenter
                    )

                    // Dynamic HUD Pill / Reticle Guide Text
                    if model.isCapturing {
                        HStack(spacing: 8) {
                            Image(systemName: model.phase.iconName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.cyan)

                            Text(model.phase.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)

                            if model.phase != .completed {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.8), Color.purple.opacity(0.6), Color.cyan.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                        )
                        .shadow(color: Color.cyan.opacity(0.35), radius: 8, y: 2)
                        .position(x: boxCenter.x, y: boxCenter.y + boxHeight / 2 + 32)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "viewfinder")
                                .font(.subheadline.weight(.semibold))
                            Text("Számlálóablak helye")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(Color.white)
                        .position(x: boxCenter.x, y: boxCenter.y + boxHeight / 2 + 28)
                        .transition(.opacity)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // 4. Tap-to-Focus Indicator
            if let focusPoint = focusVisualPoint {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.yellow, lineWidth: 1.5)
                        .frame(width: isFocusAnimating ? 60 : 75, height: isFocusAnimating ? 60 : 75)

                    Rectangle().fill(Color.yellow).frame(width: 6, height: 1.5).offset(x: isFocusAnimating ? -30 : -37.5)
                    Rectangle().fill(Color.yellow).frame(width: 6, height: 1.5).offset(x: isFocusAnimating ? 30 : 37.5)
                    Rectangle().fill(Color.yellow).frame(width: 1.5, height: 6).offset(y: isFocusAnimating ? -30 : -37.5)
                    Rectangle().fill(Color.yellow).frame(width: 1.5, height: 6).offset(y: isFocusAnimating ? 30 : 37.5)
                }
                .position(focusPoint)
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isFocusAnimating)
                .allowsHitTesting(false)
            }

            // 5. UI Controls (Top Bar & Bottom Controls)
            VStack {
                // Top Bar
                HStack {
                    // Flashlight / Torch button
                    if model.isTorchAvailable {
                        Button {
                            model.toggleTorch()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: model.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(model.isTorchOn ? Color.yellow : Color.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel(model.isTorchOn ? "Zseblámpa kikapcsolása" : "Zseblámpa bekapcsolása")
                    } else {
                        Spacer().frame(width: 44)
                    }

                    Spacer()

                    // Title Pill
                    Text("Gázóra Leolvasó")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())

                    Spacer()

                    // Settings Button
                    if let credentialStore {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Home Assistant beállítások")
                    } else {
                        Spacer().frame(width: 44)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                // Error Message
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.bottom, 8)
                }

                // Simulator Hint Banner
                if model.isSimulator {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.cyan)
                        Text("Szimulátor mód: a gombbal tesztfotó generálható a leolvasáshoz.")
                            .font(.footnote)
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                }

                // Zoom Selector (1x / 2x)
                zoomSelector
                    .padding(.bottom, 12)

                // Bottom Shutter Controls
                HStack(alignment: .center) {
                    // Left: History / Archive Button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isShowingHistory = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Image(systemName: "photo.stack.fill")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(.white)
                                )

                            if model.readingsCount > 0 {
                                Text("\(model.readingsCount)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan, in: Capsule())
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .accessibilityLabel("Leolvasási előzmények megnyitása")

                    Spacer()

                    // Center: Shutter Button
                    shutterButton

                    Spacer()

                    // Right: PhotosPicker gallery import button
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.white)
                            )
                    }
                    .accessibilityLabel("Fotó beolvasása a galériából")
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 28)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingSettings) {
            AppSettingsView(container: model.container)
        }
        .sheet(isPresented: $isShowingHistory) {
            ReadingsHistoryView(
                model: ReadingsHistoryViewModel(container: model.container),
                onSelectReading: { selectedReading in
                    Task {
                        await model.openReadingReview(reading: selectedReading)
                    }
                }
            )
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    triggerShutterEffect()
                    await model.importPhoto(data: data)
                }
                selectedPhotoItem = nil
            }
        }
        .task {
            model.configureAndStart()
            await model.refreshReadingsCount()
        }
    }

    private func triggerShutterEffect() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isShutterFlashing = true
        withAnimation(.easeOut(duration: 0.2)) {
            isShutterFlashing = false
        }
    }

    private func handleTapToFocus(devicePoint: CGPoint, viewPoint: CGPoint) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        model.focus(at: devicePoint)
        focusDismissTask?.cancel()
        focusVisualPoint = viewPoint
        isFocusAnimating = false
        withAnimation(.easeOut(duration: 0.15)) {
            isFocusAnimating = true
        }
        focusDismissTask = Task {
            try? await Task.sleep(for: .milliseconds(1400))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.3)) {
                    focusVisualPoint = nil
                    isFocusAnimating = false
                }
            }
        }
    }

    // 1x and 2x Zoom Controls
    private var zoomSelector: some View {
        HStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    currentBaseZoom = 1.0
                    model.setZoom(factor: 1.0)
                }
            } label: {
                Text("1×")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(abs(model.zoomFactor - 1.0) < 0.2 ? Color.black : Color.white)
                    .background(abs(model.zoomFactor - 1.0) < 0.2 ? Color.yellow : Color.black.opacity(0.45), in: Circle())
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    currentBaseZoom = 2.0
                    model.setZoom(factor: 2.0)
                }
            } label: {
                Text("2×")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(abs(model.zoomFactor - 2.0) < 0.2 ? Color.black : Color.white)
                    .background(abs(model.zoomFactor - 2.0) < 0.2 ? Color.yellow : Color.black.opacity(0.45), in: Circle())
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // Classic Apple-style Camera Shutter Button with Apple Intelligence Gradient during Processing
    @ViewBuilder
    private var shutterButton: some View {
        Button {
            triggerShutterEffect()
            Task { await model.capture() }
        } label: {
            ZStack {
                if model.isCapturing {
                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color.cyan,
                                    Color.blue,
                                    Color.purple,
                                    Color.pink,
                                    Color.orange,
                                    Color.cyan
                                ]),
                                center: .center
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 78, height: 78)

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                } else {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 78, height: 78)

                    Circle()
                        .fill(model.isSimulator ? Color.accentColor : Color.white)
                        .frame(width: 64, height: 64)
                        .scaleEffect(isShutterPressed ? 0.9 : 1.0)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!model.isConfigured || model.isCapturing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.1)) { isShutterPressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.15)) { isShutterPressed = false } }
        )
        .accessibilityLabel("Fénykép készítése")
    }
}

// Modern 2025/2026 Apple Intelligence style Scanning Reticle with Iridescent Aura and Laser Sweep
private struct ScanningReticleOverlay: View {
    let isScanning: Bool
    let phase: CapturePhase
    let boxWidth: CGFloat
    let boxHeight: CGFloat
    let boxCenter: CGPoint

    @State private var scanOffset: CGFloat = 0.0
    @State private var glowRotation: Double = 0.0

    var body: some View {
        ZStack {
            if isScanning {
                // Iridescent glowing blurred halo
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.cyan,
                                Color.blue,
                                Color.purple,
                                Color.pink,
                                Color.orange,
                                Color.cyan
                            ]),
                            center: .center,
                            angle: .degrees(glowRotation)
                        ),
                        lineWidth: 3.5
                    )
                    .blur(radius: 6)
                    .opacity(0.85)

                // Crisp border with iridescent gradient
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.cyan,
                                Color.blue,
                                Color.purple,
                                Color.pink,
                                Color.orange,
                                Color.cyan
                            ]),
                            center: .center,
                            angle: .degrees(glowRotation)
                        ),
                        lineWidth: 2.0
                    )

                // Active LiDAR / Vision Scanning Laser Beam
                GeometryReader { geo in
                    let beamY = scanOffset * geo.size.height

                    ZStack(alignment: .center) {
                        // Soft vertical laser gradient trail
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(0.0),
                                        Color.cyan.opacity(0.22),
                                        Color.white.opacity(0.35),
                                        Color.cyan.opacity(0.22),
                                        Color.cyan.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 32)

                        // Core bright laser line
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(0.0),
                                        Color.cyan.opacity(0.85),
                                        Color.white,
                                        Color.cyan.opacity(0.85),
                                        Color.cyan.opacity(0.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2.5)
                            .shadow(color: Color.cyan, radius: 5, y: 0)
                    }
                    .position(x: geo.size.width / 2, y: beamY)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // White corner brackets
                reticleCornerBrackets(color: Color.white.opacity(0.9))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)

                reticleCornerBrackets(color: Color.cyan)
            }
        }
        .frame(width: boxWidth, height: boxHeight)
        .position(boxCenter)
        .onAppear {
            if isScanning {
                startScanningAnimation()
            }
        }
        .onChange(of: isScanning) { _, scanning in
            if scanning {
                startScanningAnimation()
            }
        }
    }

    private func startScanningAnimation() {
        withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
            glowRotation = 360.0
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            scanOffset = 1.0
        }
    }

    private func reticleCornerBrackets(color: Color) -> some View {
        GeometryReader { geo in
            let length: CGFloat = 20
            let thick: CGFloat = 3

            // Top-left
            Path { p in
                p.move(to: CGPoint(x: 0, y: length))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: length, y: 0))
            }
            .stroke(color, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round))

            // Top-right
            Path { p in
                p.move(to: CGPoint(x: geo.size.width - length, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width, y: length))
            }
            .stroke(color, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round))

            // Bottom-left
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height - length))
                p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                p.addLine(to: CGPoint(x: length, y: geo.size.height))
            }
            .stroke(color, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round))

            // Bottom-right
            Path { p in
                p.move(to: CGPoint(x: geo.size.width - length, y: geo.size.height))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - length))
            }
            .stroke(color, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: ((CGPoint, CGPoint) -> Void)?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.onTap = onTap
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var onTap: ((CGPoint, CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: location)
        onTap?(devicePoint, location)
    }
}
