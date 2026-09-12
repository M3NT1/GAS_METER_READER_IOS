import SwiftUI
import UIKit

struct WindowFineTuneSheet: View {
    @Binding var window: NormalizedRect?
    let image: UIImage
    var isAnalyzing: Bool = false
    var onSave: ((NormalizedRect) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var workingWindow: NormalizedRect
    @State private var selectedTarget: NudgeTarget = .all
    @State private var initialWindow: NormalizedRect

    enum NudgeTarget: String, CaseIterable, Identifiable {
        case all = "Teljes keret"
        case top = "Felső él"
        case bottom = "Alsó él"
        case left = "Bal él"
        case right = "Jobb él"
        case topLeft = "Bal-Felső"
        case topRight = "Jobb-Felső"
        case bottomLeft = "Bal-Alsó"
        case bottomRight = "Jobb-Alsó"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all: return "arrow.up.and.down.and.arrow.left.and.right"
            case .top: return "arrow.up.to.line"
            case .bottom: return "arrow.down.to.line"
            case .left: return "arrow.left.to.line"
            case .right: return "arrow.right.to.line"
            case .topLeft: return "arrow.up.left"
            case .topRight: return "arrow.up.right"
            case .bottomLeft: return "arrow.down.left"
            case .bottomRight: return "arrow.down.right"
            }
        }
    }

    init(window: Binding<NormalizedRect?>, image: UIImage, isAnalyzing: Bool = false, onSave: ((NormalizedRect) -> Void)? = nil) {
        self._window = window
        self.image = image
        self.isAnalyzing = isAnalyzing
        self.onSave = onSave
        let initial = window.wrappedValue ?? NormalizedRect(left: 0.18, top: 0.40, right: 0.82, bottom: 0.58)
        _workingWindow = State(initialValue: initial)
        _initialWindow = State(initialValue: initial)
    }

    private func fitImageSize(containerSize: CGSize = CGSize(width: UIScreen.main.bounds.width, height: 300)) -> CGSize {
        guard image.size.width > 0, image.size.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return containerSize
        }
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    private var stepDelta: Double {
        1.0 / max(100.0, Double(fitImageSize().height))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. Large Photo View with Interactive Window and Loupe
                ZStack {
                    Color.black.ignoresSafeArea()

                    WindowEditorView(
                        window: Binding(
                            get: { workingWindow },
                            set: { if let val = $0 { workingWindow = val } }
                        ),
                        image: image,
                        isAnalyzing: isAnalyzing
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipped()

                // 2. Control Panel (D-Pad & Sizing)
                ScrollView {
                    VStack(spacing: 14) {
                        // Live Dimension / Pixel / Ratio Telemetry Pill
                        let fit = fitImageSize()
                        let screenPtH = max(2, Int(round((workingWindow.bottom - workingWindow.top) * Double(fit.height))))
                        let pxH = max(1, Int(round((workingWindow.bottom - workingWindow.top) * Double(image.size.height))))
                        let pxW = max(1, Int(round((workingWindow.right - workingWindow.left) * Double(image.size.width))))

                        HStack(spacing: 8) {
                            Label("\(pxW) × \(pxH) px fotó", systemImage: "camera")
                            Text("•")
                            Label("\(screenPtH) pt kijelző", systemImage: "iphone")
                                .foregroundStyle(screenPtH <= 8 ? Color.cyan : Color.primary)
                                .fontWeight(screenPtH <= 8 ? .bold : .semibold)
                            Text("•")
                            Label(String(format: "%.1f:1", workingWindow.aspectRatio), systemImage: "aspectratio")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())

                        // Target Selector Horizontal Pills
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Finomhangolandó célpont")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(NudgeTarget.allCases) { target in
                                        Button {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            selectedTarget = target
                                        } label: {
                                            HStack(spacing: 5) {
                                                Image(systemName: target.icon)
                                                    .font(.system(size: 11, weight: .semibold))
                                                Text(target.rawValue)
                                                    .font(.caption.weight(selectedTarget == target ? .bold : .medium))
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(
                                                selectedTarget == target
                                                    ? Color.accentColor
                                                    : Color(uiColor: .secondarySystemGroupedBackground),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(selectedTarget == target ? Color.white : Color.primary)
                                            .shadow(color: Color.black.opacity(selectedTarget == target ? 0.15 : 0.04), radius: 2, y: 1)
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }

                        // D-Pad and Resize Controls Row
                        HStack(spacing: 20) {
                            // Directional D-Pad (Up/Down/Left/Right)
                            dPadController

                            Divider().frame(height: 110)

                            // Size Adjustment Controls
                            sizeAdjustController
                        }
                        .padding(.vertical, 4)

                        // Helper Hint & Reset Row
                        HStack {
                            Label("A nyilakkal és fogantyúkkal pontosan a számokhoz igazíthatsz.", systemImage: "hand.tap")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Alaphelyzet") {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    workingWindow = initialWindow
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(14)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("Keret finomhangolása")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        window = workingWindow
                        onSave?(workingWindow)
                        dismiss()
                    } label: {
                        Text("Kész")
                            .fontWeight(.bold)
                    }
                }
            }
        }
    }

    // Directional Cross D-Pad
    private var dPadController: some View {
        VStack(spacing: 8) {
            // Up Button
            dPadButton(icon: "chevron.up", label: "Fel") {
                nudge(dx: 0, dy: -stepDelta)
            }

            HStack(spacing: 28) {
                // Left Button
                dPadButton(icon: "chevron.left", label: "Balra") {
                    nudge(dx: -stepDelta, dy: 0)
                }

                // Center indicator icon
                Image(systemName: "viewfinder")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.secondary)

                // Right Button
                dPadButton(icon: "chevron.right", label: "Jobbra") {
                    nudge(dx: stepDelta, dy: 0)
                }
            }

            // Down Button
            dPadButton(icon: "chevron.down", label: "Le") {
                nudge(dx: 0, dy: stepDelta)
            }
        }
    }

    // Size Adjust Controller
    private var sizeAdjustController: some View {
        let fit = fitImageSize()
        let onePtH = 1.0 / max(100.0, Double(fit.height))
        let fivePtH = 5.0 * onePtH
        let tenPtW = 10.0 / max(100.0, Double(fit.width))

        return VStack(spacing: 8) {
            Text("Keret mérete")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Width row
            VStack(alignment: .leading, spacing: 3) {
                Text("Szélesség")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Button {
                        adjustWidth(by: -tenPtW)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 44, height: 34)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("Keskenyebb")

                    Button {
                        adjustWidth(by: tenPtW)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 44, height: 34)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("Szélesebb")
                }
            }

            // Height row with 1pt and 5pt micro-adjustments
            VStack(alignment: .leading, spacing: 3) {
                Text("Magasság (akár 2 pt / vékony)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Button {
                        adjustHeight(by: -onePtH)
                    } label: {
                        Text("-1pt")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 32, height: 34)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("1 ponttal alacsonyabb")

                    Button {
                        adjustHeight(by: -fivePtH)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 34)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("Alacsonyabb")

                    Button {
                        adjustHeight(by: fivePtH)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 34)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("Magasabb")

                    Button {
                        adjustHeight(by: onePtH)
                    } label: {
                        Text("+1pt")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 32, height: 34)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("1 ponttal magasabb")
                }
            }
        }
    }

    private func dPadButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.primary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                )
        }
        .accessibilityLabel(label)
    }

    // Nudge logic
    private func nudge(dx: Double, dy: Double) {
        var w = workingWindow
        let fit = fitImageSize()
        let minW = 0.005
        let minH = max(0.0002, 2.0 / max(100.0, Double(fit.height)))

        switch selectedTarget {
        case .all:
            let width = w.right - w.left
            let height = w.bottom - w.top
            let newL = min(max(0.0, w.left + dx), 1.0 - width)
            let newT = min(max(0.0, w.top + dy), 1.0 - height)
            w = NormalizedRect(left: newL, top: newT, right: newL + width, bottom: newT + height)

        case .top:
            let newT = min(max(0.0, w.top + dy), w.bottom - minH)
            w = NormalizedRect(left: w.left, top: newT, right: w.right, bottom: w.bottom)

        case .bottom:
            let newB = max(min(1.0, w.bottom + dy), w.top + minH)
            w = NormalizedRect(left: w.left, top: w.top, right: w.right, bottom: newB)

        case .left:
            let newL = min(max(0.0, w.left + dx), w.right - minW)
            w = NormalizedRect(left: newL, top: w.top, right: w.right, bottom: w.bottom)

        case .right:
            let newR = max(min(1.0, w.right + dx), w.left + minW)
            w = NormalizedRect(left: w.left, top: w.top, right: newR, bottom: w.bottom)

        case .topLeft:
            let newL = min(max(0.0, w.left + dx), w.right - minW)
            let newT = min(max(0.0, w.top + dy), w.bottom - minH)
            w = NormalizedRect(left: newL, top: newT, right: w.right, bottom: w.bottom)

        case .topRight:
            let newR = max(min(1.0, w.right + dx), w.left + minW)
            let newT = min(max(0.0, w.top + dy), w.bottom - minH)
            w = NormalizedRect(left: w.left, top: newT, right: newR, bottom: w.bottom)

        case .bottomLeft:
            let newL = min(max(0.0, w.left + dx), w.right - minW)
            let newB = max(min(1.0, w.bottom + dy), w.top + minH)
            w = NormalizedRect(left: newL, top: w.top, right: w.right, bottom: newB)

        case .bottomRight:
            let newR = max(min(1.0, w.right + dx), w.left + minW)
            let newB = max(min(1.0, w.bottom + dy), w.top + minH)
            w = NormalizedRect(left: w.left, top: w.top, right: newR, bottom: newB)
        }

        workingWindow = w
    }

    private func adjustWidth(by delta: Double) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var w = workingWindow
        let minW = 0.005
        let currentW = w.right - w.left
        let newW = max(minW, currentW + delta)
        let diff = (newW - currentW) / 2.0
        let newL = max(0.0, w.left - diff)
        let newR = min(1.0, w.right + diff)
        w = NormalizedRect(left: newL, top: w.top, right: newR, bottom: w.bottom)
        workingWindow = w
    }

    private func adjustHeight(by delta: Double) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var w = workingWindow
        let fit = fitImageSize()
        let minH = max(0.0002, 2.0 / max(100.0, Double(fit.height)))
        let currentH = w.bottom - w.top
        let newH = max(minH, currentH + delta)
        let diff = (newH - currentH) / 2.0
        let newT = max(0.0, w.top - diff)
        let newB = min(1.0, w.bottom + diff)
        w = NormalizedRect(left: w.left, top: newT, right: w.right, bottom: newB)
        workingWindow = w
    }
}
