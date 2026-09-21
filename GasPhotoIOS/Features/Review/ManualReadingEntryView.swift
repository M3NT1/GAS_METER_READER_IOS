import SwiftUI

struct ManualReadingEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let meterRepository: any MeterRepository
    let readingRepository: any ReadingRepository
    let homeAssistantUsageSettings: HomeAssistantUsageSettings?
    var initialMeterID: String? = nil
    var onSaved: ((MeterReading) -> Void)? = nil

    @State private var meters: [Meter] = []
    @State private var selectedMeterID: String = ""
    @State private var capturedAt: Date = .now
    @State private var displayDigits: String = ""
    @State private var existingReadings: [MeterReading] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var progressionWarning: String?

    private var selectedMeter: Meter? {
        meters.first { $0.id == selectedMeterID }
    }

    private var parsedValue: ApprovedReadingValue? {
        guard let selectedMeter else { return nil }
        return try? ReadingValidator.approvedDigits(displayDigits, format: selectedMeter.format)
    }

    private var isValidFormat: Bool {
        parsedValue != nil
    }

    private var canSave: Bool {
        isValidFormat && progressionWarning == nil && !isSaving && !isLoading && selectedMeter != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                meterSection
                timestampSection
                readingInputSection
                progressionSection
                syncSection
                errorSection
            }
            .navigationTitle("Kézi leolvasás")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Mentés") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
            .task {
                await loadData()
            }
            .onChange(of: displayDigits) { _, _ in
                validateProgression()
            }
            .onChange(of: selectedMeterID) { _, _ in
                validateProgression()
            }
            .onChange(of: capturedAt) { _, _ in
                validateProgression()
            }
        }
    }

    @ViewBuilder
    private var meterSection: some View {
        Section("Mérőóra") {
            if isLoading {
                ProgressView("Mérők betöltése...")
            } else if meters.isEmpty {
                Text("Nem található mérőóra a katalógusban.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Mérő", selection: $selectedMeterID) {
                    ForEach(meters) { meter in
                        HStack {
                            Image(systemName: meterIconName(for: meter.kind))
                                .foregroundStyle(meterIconColor(for: meter.kind))
                            Text(meter.name)
                        }
                        .tag(meter.id)
                    }
                }
                .pickerStyle(.menu)

                if let selectedMeter {
                    HStack {
                        Text("Mértékegység")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(selectedMeter.kind.displayName) (\(selectedMeter.kind.unitSymbol))")
                            .font(.subheadline.weight(.medium))
                    }

                    HStack {
                        Text("Formátum")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(selectedMeter.format.previewLabel)
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var timestampSection: some View {
        Section("Időpont") {
            DatePicker(
                "Dátum és idő",
                selection: $capturedAt,
                in: ...Date.now,
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }

    @ViewBuilder
    private var readingInputSection: some View {
        Section("Mérőállás beírása") {
            if let selectedMeter {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField(placeholderText(for: selectedMeter), text: $displayDigits)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)

                    Text(selectedMeter.kind.unitSymbol)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text(formatGuidanceText(for: selectedMeter))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    if let parsed = parsedValue, !displayDigits.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Normalizált érték: \(parsed.displayValue) \(selectedMeter.kind.unitSymbol)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    } else if !displayDigits.isEmpty && !isValidFormat {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Érvénytelen formátum a mérőhöz képest")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var progressionSection: some View {
        if let warning = progressionWarning {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.headline)
                    Text(warning)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Érvényesítési hiba")
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        if let selectedMeter {
            Section("Szinkronizáció") {
                let haEnabled = homeAssistantUsageSettings?.isEnabled ?? false
                if HomeAssistantSyncPolicy.mayStartRequest(enabled: haEnabled, meter: selectedMeter) {
                    Label("A leolvasás szinkronizálásra kerül a Home Assistantba.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.blue)
                } else {
                    Label("Helyi mentés a naplóba (Home Assistant szinkronizálás kikapcsolva).", systemImage: "internaldrive")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            meters = try await meterRepository.allMeters()
            existingReadings = try await readingRepository.allReadings()
            if let initialMeterID, meters.contains(where: { $0.id == initialMeterID }) {
                selectedMeterID = initialMeterID
            } else if let first = meters.first {
                selectedMeterID = first.id
            }
            validateProgression()
        } catch {
            errorMessage = "Nem sikerült betölteni az adatokat."
        }
    }

    private func validateProgression() {
        progressionWarning = nil
        guard let selectedMeter, let parsed = parsedValue else { return }
        let candidate = MeterReading(
            meterID: selectedMeter.id,
            photoID: nil,
            capturedAt: capturedAt,
            status: .approvedLocal
        )
        do {
            try ReadingProgressionValidator.validate(
                candidate: candidate,
                approved: parsed,
                meter: selectedMeter,
                allReadings: existingReadings
            )
        } catch {
            progressionWarning = error.localizedDescription
        }
    }

    private func save() async {
        guard let selectedMeter, let parsed = parsedValue else { return }
        isSaving = true
        defer { isSaving = false }

        let candidate = MeterReading(
            meterID: selectedMeter.id,
            photoID: nil,
            capturedAt: capturedAt,
            status: .approvedLocal
        )

        do {
            try ReadingProgressionValidator.validate(
                candidate: candidate,
                approved: parsed,
                meter: selectedMeter,
                allReadings: existingReadings
            )
        } catch {
            progressionWarning = error.localizedDescription
            return
        }

        let haEnabled = homeAssistantUsageSettings?.isEnabled ?? false
        let initialStatus: ReadingStatus = HomeAssistantSyncPolicy.mayStartRequest(enabled: haEnabled, meter: selectedMeter)
            ? .pendingSync
            : .approvedLocal

        let reading = MeterReading(
            id: candidate.id,
            revision: 0,
            meterID: selectedMeter.id,
            photoID: nil,
            capturedAt: capturedAt,
            window: nil,
            proposal: nil,
            approvedDigits: parsed.displayValue,
            status: initialStatus,
            modelVersion: nil,
            lastSyncError: nil
        )

        do {
            try await readingRepository.insert(reading)
            onSaved?(reading)
            dismiss()
        } catch {
            errorMessage = "A mentés sikertelen: \(error.localizedDescription)"
        }
    }

    private func placeholderText(for meter: Meter) -> String {
        if meter.format.fractionalDigits > 0 {
            let intPart = String(repeating: "0", count: max(1, meter.format.integerDigits - 1)) + "1"
            let fracPart = String(repeating: "0", count: meter.format.fractionalDigits)
            return "\(intPart),\(fracPart)"
        } else {
            return String(repeating: "0", count: max(1, meter.format.integerDigits - 1)) + "1"
        }
    }

    private func formatGuidanceText(for meter: Meter) -> String {
        if meter.format.fractionalDigits > 0 {
            return "Legfeljebb \(meter.format.integerDigits) egész és \(meter.format.fractionalDigits) tizedes jegy. Vessző vagy pont használható."
        } else {
            return "Legfeljebb \(meter.format.integerDigits) egész számjegy, tizedesjegy nélkül."
        }
    }

    private func meterIconName(for kind: MeterKind) -> String {
        switch kind {
        case .electricity: return "bolt.fill"
        case .gas: return "flame.fill"
        case .water: return "drop.fill"
        }
    }

    private func meterIconColor(for kind: MeterKind) -> Color {
        switch kind {
        case .electricity: return .yellow
        case .gas: return .orange
        case .water: return .cyan
        }
    }
}
