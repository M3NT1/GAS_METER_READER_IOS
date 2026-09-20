import SwiftUI
import UIKit

struct ReadingsHistoryView: View {
    @Bindable var model: ReadingsHistoryViewModel
    var onSelectReading: ((MeterReading) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var readingToDelete: MeterReading? = nil
    @State private var isShowingDeleteConfirm = false
    @State private var isShowingTraining = false
    @State private var isShowingConsumption = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Summary KPI Cards
                summaryCards
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Segmented Filter
                Picker("Szűrő", selection: $model.selectedFilter) {
                    ForEach(ReadingsHistoryViewModel.Filter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Status message banner
                if let msg = model.statusMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(msg)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12), in: Capsule())
                    .padding(.bottom, 4)
                }

                if let err = model.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.12), in: Capsule())
                    .padding(.bottom, 4)
                }

                // Smart Training Banner
                if model.trainingCount >= 40 {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isShowingTraining = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.purple)
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Készen áll a modelltanítás!")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text("Összegyűlt \(model.trainingCount) minősített mintád a finomhangoláshoz.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Indítás")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.purple)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.purple)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }

                // Readings List
                if model.filteredReadings.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(model.filteredReadings) { reading in
                            readingRow(reading)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await model.load()
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Leolvasási napló")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bezárás") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isShowingConsumption = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                Text("Fogyasztás")
                            }
                            .font(.caption.weight(.semibold))
                        }

                        if model.pendingCount > 0 {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                Task { await model.syncAllPending() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Feltöltés (\(model.pendingCount))")
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .task {
                await model.load()
            }
            .confirmationDialog(
                "Biztosan törölni szeretnéd ezt a leolvasást?",
                isPresented: $isShowingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Törlés", role: .destructive) {
                    if let reading = readingToDelete {
                        Task { await model.delete(reading: reading) }
                    }
                    readingToDelete = nil
                }
                Button("Mégse", role: .cancel) {
                    readingToDelete = nil
                }
            }
            .sheet(isPresented: $isShowingTraining) {
                ModelTrainingView(
                    model: ModelTrainingViewModel(
                        trainingExampleStore: model.container.trainingExampleStore,
                        trainingService: model.container.trainingService
                    )
                )
            }
            .sheet(isPresented: $isShowingConsumption) {
                MeterConsumptionView(
                    meters: model.meters,
                    readings: model.readings
                )
            }
        }
    }

    // Summary Metric Cards
    private var summaryCards: some View {
        HStack(spacing: 12) {
            statCard(
                title: "Összes fotó",
                value: "\(model.readings.count)",
                icon: "photo.stack",
                color: .blue
            )

            statCard(
                title: "Feltöltendő",
                value: "\(model.pendingCount)",
                icon: "arrow.up.circle",
                color: model.pendingCount > 0 ? .orange : .secondary
            )

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isShowingTraining = true
            } label: {
                statCard(
                    title: "Tanítóminta",
                    value: "\(model.trainingCount)",
                    icon: "brain.head.profile",
                    color: .cyan
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Spacer()
            }
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // Reading Card Row
    private func readingRow(_ reading: MeterReading) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // Photo Thumbnail
                if let url = model.photoURL(for: reading.photoID),
                   let uiImage = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }

                // Info Section
                VStack(alignment: .leading, spacing: 4) {
                    // Reading Digits
                    if let approved = reading.approvedDigits {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(approved)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("m³")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else if let proposal = reading.proposal {
                        let formatted = formatProposal(proposal.digits)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(formatted)
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("m³")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Számlálókeret keresése...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Timestamp
                    Text(reading.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // Status Pill
                    statusPill(reading.status, error: reading.lastSyncError)
                }

                Spacer()

                // More Menu Button
                Menu {
                    Button {
                        onSelectReading?(reading)
                        dismiss()
                    } label: {
                        Label("Megnyitás & Módosítás", systemImage: "slider.horizontal.3")
                    }

                    if reading.status == .pendingSync || reading.approvedDigits != nil {
                        Button {
                            Task { await model.sync(reading: reading) }
                        } label: {
                            Label("Feltöltés most", systemImage: "arrow.up.circle")
                        }
                    }

                    Button {
                        Task { await model.registerAsTrainingExample(reading: reading) }
                    } label: {
                        Label("Mentés tanítómintaként", systemImage: "brain.head.profile")
                    }

                    Divider()

                    Button(role: .destructive) {
                        readingToDelete = reading
                        isShowingDeleteConfirm = true
                    } label: {
                        Label("Törlés", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
            }

            // Quick Actions Bar
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelectReading?(reading)
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Módosítás")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if reading.status == .pendingSync {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await model.sync(reading: reading) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Feltöltés")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                } else if reading.status == .synced {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Szinkronizálva")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else if reading.status == .approvedLocal {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Helyben mentve")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func statusPill(_ status: ReadingStatus, error: String?) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .needsReview, .positionIdentified, .counterRecognized:
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text("Jóváhagyásra vár")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            case .pendingSync:
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text("Feltöltésre vár")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
            case .synced:
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Home Assistant szinkronizálva")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
            case .approvedLocal:
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text("Helyben mentve")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
    }

    private func formatProposal(_ digits: String) -> String {
        guard digits.count == 8 else { return digits }
        let index = digits.index(digits.startIndex, offsetBy: 5)
        return String(digits[..<index]) + "." + String(digits[index...])
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Nincs megjeleníthető leolvasás")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Készíts egy új fotót a kamerával, vagy olvass be egy képet a fotótáradból.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}
