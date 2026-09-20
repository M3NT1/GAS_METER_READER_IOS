import SwiftUI
import UIKit

struct ReviewView: View {
    @Bindable var model: ReviewViewModel
    let photoURL: URL?
    var onRetake: (() -> Void)? = nil

    @State private var displayDigits: String
    @State private var window: NormalizedRect?
    @State private var isShowingFineTune = false

    init(model: ReviewViewModel, photoURL: URL?, onRetake: (() -> Void)? = nil) {
        self.model = model
        self.photoURL = photoURL
        self.onRetake = onRetake
        _displayDigits = State(initialValue: model.reading.approvedDigits ?? Self.formattedProposal(model.reading.proposal?.digits))
        let initialWindow = model.reading.window ?? NormalizedRect(left: 0.18, top: 0.40, right: 0.82, bottom: 0.58)
        _window = State(initialValue: initialWindow)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Photo Card with Bounding Box
                photoCard

                // 2. Analog Roller Dials Card
                dialsCard

                // 3. Status & Details Card
                detailsCard

                // 4. Action Buttons
                actionSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Gázóra ellenőrzése")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if let onRetake {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onRetake()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                            Text("Új fotó")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingFineTune) {
            if let image = model.displayImage {
                WindowFineTuneSheet(
                    window: $window,
                    image: image,
                    isAnalyzing: model.isAnalyzingWindow
                ) { newWindow in
                    Task {
                        if let newDigits = await model.updateWindow(newWindow) {
                            withAnimation {
                                displayDigits = newDigits
                            }
                        }
                    }
                }
            }
        }
    }

    // Photo Preview Card
    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Felismerési zóna", systemImage: "viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if model.isAnalyzingWindow {
                    ProgressView()
                        .controlSize(.small)
                    Text("Elemzés...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if model.displayImage != nil {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isShowingFineTune = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                Text("Finomhangolás")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }

                    if window != nil {
                        Button("Alaphelyzet") {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation {
                                window = model.reading.window ?? NormalizedRect(left: 0.18, top: 0.40, right: 0.82, bottom: 0.58)
                            }
                        }
                        .font(.caption.weight(.medium))
                    }
                }
            }

            ZStack {
                if let image = model.displayImage {
                    WindowEditorView(
                        window: $window,
                        image: image,
                        isAnalyzing: model.isAnalyzingWindow
                    ) { newWindow in
                        Task {
                            if let newDigits = await model.updateWindow(newWindow) {
                                withAnimation {
                                    displayDigits = newDigits
                                }
                            }
                        }
                    }
                } else if model.isLoadingDisplayImage {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.regular)
                        Text("Fotó előkészítése...")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Nincs fotó", systemImage: "camera")
                        .frame(height: 240)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 6) {
                Image(systemName: "hand.draw.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("A kék keret sarkait és közepét húzva igazítsd a számlálótárcsákra.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    // Digital Gas Meter Roller Dials Card
    private var dialsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Leolvasott állás", systemImage: "gauge.with.needle")
                    .font(.headline)
                Spacer()
                Text(model.reading.proposal == nil ? "Kézi bevitel" : "Helyi AI javaslat")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            if model.isAnalyzingWindow {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.accentColor)
                    Text("Számjegyek újraszámolása a módosított keret alapján...")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Analog Roller Dials View
            RollerDialsView(
                displayDigits: $displayDigits,
                uncertainPositions: model.reading.proposal?.uncertainPositions ?? []
            )
            .opacity(model.isAnalyzingWindow ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: model.isAnalyzingWindow)

            // Uncertain warning if needed
            if let proposal = model.reading.proposal, !proposal.uncertainPositions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                    Text("A narancssárga ponttal jelölt görgők bizonytalanok. Érintsd meg a javításhoz!")
                        .font(.footnote)
                        .foregroundStyle(Color.orange)
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 0) {
                Text("5 fekete görgő: egész m³ • ")
                Text("3 piros görgő: tizedesek").foregroundStyle(Color.red)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    // Details & Sync Card
    private var detailsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Rögzítés ideje", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.reading.capturedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.subheadline.weight(.medium))
            }

            Divider()

            HStack {
                Label("Home Assistant állapot", systemImage: "house")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.status == .synced {
                    Label("Szinkronizálva", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.green)
                } else if model.status == .pendingSync {
                    Label("Feltöltésre vár", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.orange)
                } else {
                    Text("Jóváhagyásra vár")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let lastError = model.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    // Action Section
    private var actionSection: some View {
        VStack(spacing: 12) {
            if model.status == .pendingSync {
                // Step 2: Reading is saved locally, now offer explicit upload to Home Assistant
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.green)
                            .font(.subheadline)
                        Text("Állás rögzítve helyben. Készen áll a feltöltésre.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 2)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await model.syncApprovedReading() }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isSyncing {
                                ProgressView()
                                    .tint(.white)
                                    .controlSize(.small)
                                Text("Feltöltés folyamatban...")
                                    .font(.headline.weight(.semibold))
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.headline)
                                Text("Feltöltés a Home Assistantba")
                                    .font(.headline.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(model.isSyncing ? Color.accentColor.opacity(0.7) : Color.accentColor)
                        )
                        .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSyncing)
                }
            } else if model.status == .synced {
                // Already synced to Home Assistant
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                            .font(.title3)
                        Text("Sikeresen feltöltve a Home Assistantba!")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.green)
                    }
                    .padding(.vertical, 4)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await model.syncApprovedReading() }
                    } label: {
                        HStack(spacing: 6) {
                            if model.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Szinkronizálás...")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Újraküldés a Home Assistantba")
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.accentColor, lineWidth: 1.5)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSyncing)
                }
            } else {
                // Step 1: User reviews and approves locally
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await model.approve(displayDigits: displayDigits, window: window) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.headline)
                        Text("Helyi jóváhagyás és mentés")
                            .font(.headline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(model.canApprove(displayDigits: displayDigits) && !model.isAnalyzingWindow ? Color.accentColor : Color.gray.opacity(0.3))
                    )
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .disabled(!model.canApprove(displayDigits: displayDigits) || model.isAnalyzingWindow)
            }
        }
        .padding(.top, 6)
    }

    private static func formattedProposal(_ digits: String?) -> String {
        guard let digits, digits.count == 8 else { return "" }
        let index = digits.index(digits.startIndex, offsetBy: 5)
        return String(digits[..<index]) + "." + String(digits[index...])
    }
}
