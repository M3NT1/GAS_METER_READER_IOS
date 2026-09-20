import SwiftUI

struct MeterConsumptionView: View {
    let meters: [Meter]
    let readings: [MeterReading]
    @State private var selectedMeterID: String
    @Environment(\.dismiss) private var dismiss

    init(meters: [Meter], readings: [MeterReading], initialMeterID: String? = nil) {
        self.meters = meters
        self.readings = readings
        let initialID = initialMeterID ?? meters.first?.id ?? "gas_main"
        _selectedMeterID = State(initialValue: initialID)
    }

    private var currentMeter: Meter? {
        meters.first(where: { $0.id == selectedMeterID }) ?? meters.first
    }

    private var calculationResult: Result<[ConsumptionInterval], Error> {
        guard let currentMeter else { return .success([]) }
        do {
            let intervals = try ConsumptionCalculator.intervals(readings: readings, meter: currentMeter)
            return .success(intervals)
        } catch {
            return .failure(error)
        }
    }

    private var intervals: [ConsumptionInterval] {
        if case let .success(list) = calculationResult {
            return list
        }
        return []
    }

    private var totalConsumption: Decimal? {
        guard !intervals.isEmpty else { return nil }
        return intervals.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var dateRangeText: String? {
        guard let first = intervals.first, let last = intervals.last else { return nil }
        let calendar = Calendar.current
        let days = max(1, calendar.dateComponents([.day], from: first.start, to: last.end).day ?? 1)
        let startStr = first.start.formatted(date: .abbreviated, time: .omitted)
        let endStr = last.end.formatted(date: .abbreviated, time: .omitted)
        return "\(startStr) – \(endStr) (\(days) nap)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Meter Picker (if multiple meters)
                if meters.count > 1 {
                    Picker("Mérőóra", selection: $selectedMeterID) {
                        ForEach(meters) { meter in
                            HStack {
                                Text(meter.name)
                                Text("(\(meter.kind.unitSymbol))")
                            }
                            .tag(meter.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }

                // Error Banner
                if case let .failure(error) = calculationResult {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error.localizedDescription)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                // Summary KPI Header
                if let meter = currentMeter {
                    summaryCard(for: meter)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                // Intervals List
                if intervals.isEmpty {
                    emptyStateView
                } else {
                    List {
                        Section(header: Text("FOGYASZTÁSI INTERVALLUMOK (\(intervals.count))").font(.caption.weight(.semibold))) {
                            ForEach(intervals.reversed()) { interval in
                                intervalRow(interval, meter: currentMeter)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Fogyasztás")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bezárás") { dismiss() }
                }
            }
        }
    }

    private func summaryCard(for meter: Meter) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meter.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let range = dateRangeText {
                        Text(range)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: iconName(for: meter.kind))
                    .font(.title2)
                    .foregroundStyle(iconColor(for: meter.kind))
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text("Összes fogyasztás:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let total = totalConsumption {
                    Text("\(formatAmount(total, format: meter.format)) \(meter.kind.unitSymbol)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                } else {
                    Text("—")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func intervalRow(_ interval: ConsumptionInterval, meter: Meter?) -> some View {
        let format = meter?.format ?? MeterFormat(integerDigits: 5, fractionalDigits: 3)
        let unit = meter?.kind.unitSymbol ?? ""
        let calendar = Calendar.current
        let days = max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(interval.start.formatted(date: .abbreviated, time: .shortened)) → \(interval.end.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(days) nap")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(formatAmount(interval.fromValue, format: format)) → \(formatAmount(interval.toValue, format: format)) \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("+\(formatAmount(interval.amount, format: format)) \(unit)")
                    .font(.system(.body, design: .monospaced, weight: .bold))
                    .foregroundStyle(Color.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("Még nincs elegendő adat")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("A fogyasztás kiszámításához legalább két jóváhagyott leolvasásra van szükség ugyanehhez a mérőórához.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatAmount(_ amount: Decimal, format: MeterFormat) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = format.fractionalDigits
        formatter.maximumFractionDigits = format.fractionalDigits
        formatter.locale = Locale(identifier: "hu_HU")
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    private func iconName(for kind: MeterKind) -> String {
        switch kind {
        case .electricity: "bolt.fill"
        case .gas: "flame.fill"
        case .water: "drop.fill"
        }
    }

    private func iconColor(for kind: MeterKind) -> Color {
        switch kind {
        case .electricity: .yellow
        case .gas: .orange
        case .water: .blue
        }
    }
}
