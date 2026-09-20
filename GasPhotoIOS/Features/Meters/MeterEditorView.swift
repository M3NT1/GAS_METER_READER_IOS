import SwiftUI

struct MeterEditorView: View {
    let meter: Meter?
    let meterRepository: any MeterRepository
    let readingRepository: any ReadingRepository
    var onSave: ((Meter) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var kind: MeterKind = .gas
    @State private var integerDigits: Int = 5
    @State private var fractionalDigits: Int = 3
    @State private var recognition: RecognitionProfile = .manual
    @State private var isArchived: Bool = false
    @State private var hasReadings: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    private var isNew: Bool { meter == nil }

    private var canUseLegacyGasAI: Bool {
        kind == .gas && integerDigits == 5 && fractionalDigits == 3
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1...9).contains(integerDigits) &&
        (0...3).contains(fractionalDigits)
    }

    var body: some View {
        Form {
            // 1. Basic Info
            Section {
                TextField("Mérőóra neve (pl. Fő gázóra)", text: $name)
                    .accessibilityLabel("Mérőóra neve")

                if hasReadings {
                    HStack {
                        Text("Kategória")
                        Spacer()
                        Text(kindTitle(kind))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Kategória", selection: $kind) {
                        ForEach(MeterKind.allCases, id: \.self) { k in
                            Text(kindTitle(k)).tag(k)
                        }
                    }
                    .onChange(of: kind) { _, newKind in
                        adjustDefaultsForKind(newKind)
                    }
                }
            } header: {
                Text("Alapadatok")
            }

            // 2. Format & Display
            Section {
                if hasReadings {
                    HStack {
                        Text("Számjegyek formátuma")
                        Spacer()
                        Text("\(integerDigits) egész + \(fractionalDigits) tizedes (\(kind.unitSymbol))")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Stepper("Egész számjegyek: \(integerDigits)", value: $integerDigits, in: 1...9)
                        .onChange(of: integerDigits) { _, _ in
                            validateRecognitionCompatibility()
                        }

                    Stepper("Tizedesjegyek: \(fractionalDigits)", value: $fractionalDigits, in: 0...3)
                        .onChange(of: fractionalDigits) { _, _ in
                            validateRecognitionCompatibility()
                        }

                    HStack {
                        Text("Mértékegység")
                        Spacer()
                        Text(kind.unitSymbol)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Számláló formátuma")
            } footer: {
                if hasReadings {
                    Text("Ehhez a mérőhöz már rögzítve van leolvasás. Az adatintegritás megőrzése érdekében a kategória és a formátum nem módosítható.")
                } else {
                    Text("Állítsd be a fizikai mérőórádon látható számlálógörgők számát.")
                }
            }

            // 3. Recognition Profile
            Section {
                if hasReadings {
                    HStack {
                        Text("Felismerés módja")
                        Spacer()
                        Text(recognition == .legacyGas8 ? "AI Gázóra (8 jegy)" : "Kézi bevitel")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Felismerés módja", selection: $recognition) {
                        Text("Kézi bevitel").tag(RecognitionProfile.manual)
                        if canUseLegacyGasAI {
                            Text("AI Gázóra (5 egész + 3 tizedes)").tag(RecognitionProfile.legacyGas8)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Felismerési profil")
            } footer: {
                if !canUseLegacyGasAI && !hasReadings {
                    Text("A helyi AI felismerőmodell kizárólag a szabványos 5+3 számjegyes gázórákat támogatja. Más formátumhoz és mérőtípushoz a kézi bevitel érhető el.")
                }
            }

            // 4. Archive / Status
            if !isNew {
                Section {
                    Toggle("Mérőóra archiválása", isOn: $isArchived)
                } header: {
                    Text("Állapot")
                } footer: {
                    Text("Az archivált mérőhöz nem indítható új fotózás, de a korábbi leolvasási napló és a fogyasztási adatok megmaradnak.")
                }
            }

            // Error message
            if let errorMessage {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Új mérőóra" : "Mérőóra szerkesztése")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Mégse") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Mentés") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(!isFormValid || isSaving)
            }
        }
        .task {
            loadInitialData()
        }
    }

    private func loadInitialData() {
        if let meter {
            name = meter.name
            kind = meter.kind
            integerDigits = meter.format.integerDigits
            fractionalDigits = meter.format.fractionalDigits
            recognition = meter.recognition
            isArchived = meter.isArchived

            Task {
                let allReadings = (try? await readingRepository.allReadings()) ?? []
                hasReadings = allReadings.contains { $0.meterID == meter.id }
            }
        } else {
            adjustDefaultsForKind(kind)
        }
    }

    private func adjustDefaultsForKind(_ k: MeterKind) {
        switch k {
        case .electricity:
            integerDigits = 6
            fractionalDigits = 3
            recognition = .manual
        case .gas:
            integerDigits = 5
            fractionalDigits = 3
            recognition = .legacyGas8
        case .water:
            integerDigits = 5
            fractionalDigits = 3
            recognition = .manual
        }
    }

    private func validateRecognitionCompatibility() {
        if !canUseLegacyGasAI {
            recognition = .manual
        }
    }

    private func kindTitle(_ k: MeterKind) -> String {
        switch k {
        case .electricity: return "Villanyóra"
        case .gas: return "Gázóra"
        case .water: return "Vízóra"
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Kérlek, adj meg egy érvényes nevet a mérőórának."
            return
        }

        guard let format = MeterFormat(validating: integerDigits, fractionalDigits: fractionalDigits) else {
            errorMessage = "A megadott számjegyformátum érvénytelen."
            return
        }

        let meterToSave: Meter
        if let existing = meter {
            meterToSave = Meter(
                id: existing.id,
                name: trimmedName,
                kind: existing.kind,
                format: existing.format,
                recognition: existing.recognition,
                isArchived: isArchived
            )
        } else {
            meterToSave = Meter(
                id: UUID().uuidString,
                name: trimmedName,
                kind: kind,
                format: format,
                recognition: canUseLegacyGasAI ? recognition : .manual,
                isArchived: false
            )
        }

        do {
            try await meterRepository.save(meterToSave)
            onSave?(meterToSave)
            dismiss()
        } catch {
            errorMessage = "A mentés sikertelen: \(error.localizedDescription)"
        }
    }
}
