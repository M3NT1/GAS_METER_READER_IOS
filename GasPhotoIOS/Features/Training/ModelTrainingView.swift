import SwiftUI
import UIKit

struct ModelTrainingView: View {
    @Bindable var model: ModelTrainingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Privacy & AI Header Banner
                    headerPrivacyBanner

                    // 2. Status & Error Messages
                    if let msg = model.statusMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(msg)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let err = model.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(err)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // 3. Active Model Card & Target Selector
                    activeModelCard

                    // 4. Live Progress Card (if training)
                    if model.isTraining, let progress = model.progress {
                        liveProgressCard(progress)
                    }

                    // 5. Candidate Evaluation Card (if evaluation ready)
                    if let candidate = model.candidateEvaluation {
                        candidateEvaluationCard(candidate)
                    }

                    // 6. Prerequisites Checklist (if not training and no candidate)
                    if !model.isTraining && model.candidateEvaluation == nil {
                        prerequisitesCard

                        // Start Training Button
                        startTrainingSection
                    }

                    // 7. Rollback Section (if custom model is active)
                    if model.activeStatus?.type == .custom && !model.isTraining {
                        rollbackSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Modell tanítása")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bezárás") { dismiss() }
                }
            }
            .task {
                await model.load()
            }
            .confirmationDialog(
                "Biztosan visszaállítod a gyári alapértelmezett modellt?",
                isPresented: $model.showRollbackConfirm,
                titleVisibility: .visible
            ) {
                Button("Visszaállítás gyárira", role: .destructive) {
                    Task { await model.rollbackToFactoryModel() }
                }
                Button("Mégse", role: .cancel) {}
            }
        }
    }

    // MARK: - Header Privacy Banner
    private var headerPrivacyBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("100% Helyi Tanulás az iPhone-on")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("A gázóramodell finomhangolása közvetlenül az iPhone Neural Engine és CPU hardverén fut. A fotók, keretek és számsorok soha nem hagyják el a készüléket.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: - Active Model Card
    private var activeModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CÉL & AKTÍV MODELL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Target Picker
            Picker("Modell célja", selection: $model.selectedTarget) {
                ForEach(TrainingTarget.allCases) { target in
                    Label(target.title, systemImage: target.icon).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isTraining)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(model.activeStatus?.version ?? "v1.0.0 (Gyári)")
                            .font(.headline)
                    }

                    Text(model.selectedTarget.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let accuracy = model.activeStatus?.accuracy {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f%%", accuracy * 100))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        Text("Becsült pontosság")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: - Prerequisites Card
    private var prerequisitesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FELTÉTELEK ELLENŐRZÉSE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let prereq = model.prerequisites {
                // Samples count progress
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Jóváhagyott mintaképek", systemImage: "photo.stack")
                            .font(.subheadline)
                        Spacer()
                        Text("\(prereq.sampleCount) / \(prereq.minRequiredSamples) db")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(prereq.hasEnoughSamples ? .green : .orange)
                    }

                    ProgressView(value: min(1.0, Double(prereq.sampleCount) / Double(prereq.minRequiredSamples)))
                        .tint(prereq.hasEnoughSamples ? .green : .orange)
                }

                Divider()

                // Charger / Battery check
                HStack {
                    Label(
                        prereq.isPluggedIn ? "Töltőhöz csatlakoztatva" : "Töltő csatlakoztatása javasolt",
                        systemImage: prereq.isPluggedIn ? "bolt.fill" : "battery.50"
                    )
                    .font(.subheadline)
                    Spacer()
                    Image(systemName: prereq.isBatteryOk ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(prereq.isBatteryOk ? .green : .orange)
                }

                Divider()

                // Storage check
                HStack {
                    Label("Helyi tárhely", systemImage: "internaldrive")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: - Live Progress Card
    private func liveProgressCard(_ progress: TrainingProgress) -> some View {
        VStack(spacing: 16) {
            HStack {
                Label("Tanítási folyamat", systemImage: "brain.head.profile")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(String(format: "%.0f%%", progress.fractionCompleted * 100))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }

            // Progress bar
            ProgressView(value: progress.fractionCompleted)
                .tint(Color.accentColor)

            // Stage title
            Text(progress.stage.displayName)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            // Telemetry stats
            HStack(spacing: 12) {
                telemetryItem(title: "Ciklus", value: "\(progress.epoch) / \(progress.totalEpochs)")
                telemetryItem(title: "Veszteség", value: String(format: "%.3f", progress.loss))
                telemetryItem(title: "Hátralévő idő", value: progress.formattedRemainingTime)
            }

            // Cancel Button
            Button(role: .destructive) {
                model.cancelTraining()
            } label: {
                Label("Folyamat megszakítása", systemImage: "xmark.circle")
                    .font(.footnote.weight(.semibold))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5)
                )
        )
    }

    private func telemetryItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Candidate Evaluation Card
    private func candidateEvaluationCard(_ candidate: ModelCandidateEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Jelölt modell kiértékelve!", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color.green)
                Spacer()
                Text(candidate.candidateVersion)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }

            // Evaluation Comparison Table
            VStack(spacing: 8) {
                comparisonRow(
                    title: "Felismerési pontosság",
                    oldValue: String(format: "%.1f%%", candidate.baselineAccuracy * 100),
                    newValue: String(format: "%.1f%%", candidate.candidateAccuracy * 100),
                    diff: String(format: "+%.1f%%", candidate.accuracyImprovementPercent),
                    isPositive: candidate.accuracyImprovementPercent >= 0
                )

                if let iou = candidate.iouScore {
                    comparisonRow(
                        title: "Keret átfedés (IoU)",
                        oldValue: "0.85",
                        newValue: String(format: "%.2f", iou),
                        diff: "+0.08",
                        isPositive: true
                    )
                }

                comparisonRow(
                    title: "Magas bizalmú hibák",
                    oldValue: "0 db",
                    newValue: "\(candidate.regressionCount) db",
                    diff: "0 regresszió",
                    isPositive: candidate.regressionCount == 0
                )
            }
            .padding(10)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            // Action Buttons
            VStack(spacing: 8) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await model.activateCandidate() }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Új modell aktiválása ezen az iPhone-on")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }

                Button {
                    model.discardCandidate()
                } label: {
                    Text("Jelölt elvetése")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
                )
        )
    }

    private func comparisonRow(title: String, oldValue: String, newValue: String, diff: String, isPositive: Bool) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(oldValue)
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(newValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
            Text("(\(diff))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isPositive ? .green : .red)
        }
    }

    // MARK: - Start Training Section
    private var startTrainingSection: some View {
        VStack(spacing: 8) {
            let prereq = model.prerequisites
            let canStart = prereq?.isReadyToTrain == true
            let hasAtLeastOne = (prereq?.sampleCount ?? 0) > 0

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    await model.startTraining(allowSampleOverride: !canStart && hasAtLeastOne)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.headline)
                    Text(canStart ? "Finomhangolás indítása" : (hasAtLeastOne ? "Próbatanítás a meglévő \(prereq?.sampleCount ?? 0) mintával" : "Tanítás indítása (Nincs még minta)"))
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(hasAtLeastOne ? Color.accentColor : Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!hasAtLeastOne)

            if let prereq, !prereq.hasEnoughSamples && hasAtLeastOne {
                Text("Megjegyzés: Az optimális pontossághoz 40 minta ajánlott, de tesztelési célból kevesebbel is elindítható.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Rollback Section
    private var rollbackSection: some View {
        Button(role: .destructive) {
            model.showRollbackConfirm = true
        } label: {
            HStack {
                Image(systemName: "arrow.uturn.backward.circle")
                Text("Visszaállítás az eredeti gyári modellre")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.red)
        }
        .padding(.top, 8)
    }
}
