import SwiftUI

struct MeterListView: View {
    let meterRepository: any MeterRepository
    let readingRepository: any ReadingRepository

    @State private var meters: [Meter] = []
    @State private var isShowingCreateSheet = false
    @State private var selectedMeterToEdit: Meter? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    private var activeMeters: [Meter] {
        meters.filter { !$0.isArchived }
    }

    private var archivedMeters: [Meter] {
        meters.filter { $0.isArchived }
    }

    var body: some View {
        List {
            // 1. Active Meters
            Section {
                if activeMeters.isEmpty && !isLoading {
                    Text("Nincs rögzített aktív mérőóra.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeMeters) { meter in
                        meterRow(meter)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMeterToEdit = meter
                            }
                    }
                }
            } header: {
                Text("Aktív mérők")
            }

            // 2. Archived Meters
            if !archivedMeters.isEmpty {
                Section {
                    ForEach(archivedMeters) { meter in
                        meterRow(meter)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMeterToEdit = meter
                            }
                    }
                } header: {
                    Text("Archivált mérők")
                } footer: {
                    Text("Az archivált mérők leolvasási naplója megmarad, de a kamera választójában nem jelennek meg.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Mérőórák")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Új mérőóra hozzáadása")
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            NavigationStack {
                MeterEditorView(
                    meter: nil,
                    meterRepository: meterRepository,
                    readingRepository: readingRepository
                ) { _ in
                    Task { await loadMeters() }
                }
            }
        }
        .sheet(item: $selectedMeterToEdit) { meter in
            NavigationStack {
                MeterEditorView(
                    meter: meter,
                    meterRepository: meterRepository,
                    readingRepository: readingRepository
                ) { _ in
                    Task { await loadMeters() }
                }
            }
        }
        .task {
            await loadMeters()
        }
        .refreshable {
            await loadMeters()
        }
    }

    private func meterRow(_ meter: Meter) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconBackgroundColor(for: meter.kind).gradient)
                    .frame(width: 36, height: 36)
                Image(systemName: iconName(for: meter.kind))
                    .foregroundStyle(.white)
                    .font(.system(size: 18, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(meter.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    if meter.isArchived {
                        Text("Archivált")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Text("\(meter.format.integerDigits)+\(meter.format.fractionalDigits) jegy (\(meter.kind.unitSymbol))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(meter.recognition == .legacyGas8 ? "AI Felismerés" : "Kézi bevitel")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(meter.recognition == .legacyGas8 ? Color.purple : Color.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func iconName(for kind: MeterKind) -> String {
        switch kind {
        case .electricity: return "bolt.fill"
        case .gas: return "flame.fill"
        case .water: return "drop.fill"
        }
    }

    private func iconBackgroundColor(for kind: MeterKind) -> Color {
        switch kind {
        case .electricity: return .yellow
        case .gas: return .orange
        case .water: return .cyan
        }
    }

    private func loadMeters() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            meters = try await meterRepository.allMeters()
        } catch {
            errorMessage = "A mérők betöltése nem sikerült: \(error.localizedDescription)"
        }
    }
}
