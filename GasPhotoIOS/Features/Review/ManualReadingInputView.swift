import SwiftUI
import UIKit

struct ManualReadingInputView: View {
    let meter: Meter
    let displayImage: UIImage?
    let isLoadingImage: Bool
    @Binding var displayDigits: String

    private var isValid: Bool {
        (try? ReadingValidator.approvedDigits(displayDigits, format: meter.format)) != nil
    }

    private var parsedDisplayValue: String? {
        try? ReadingValidator.approvedDigits(displayDigits, format: meter.format).displayValue
    }

    var body: some View {
        VStack(spacing: 16) {
            // 1. Photo Preview Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Fotó a mérőről", systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }

                ZStack {
                    if let displayImage {
                        Image(uiImage: displayImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if isLoadingImage {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.secondary)
                            Text("Kép betöltése...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                    } else {
                        ContentUnavailableView("Nincs fotó", systemImage: "camera.metering.unknown")
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                    }
                }
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            )

            // 2. Manual Reading Input Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Mérőállás beírása", systemImage: "pencil.and.list.clipboard")
                        .font(.headline)
                    Spacer()
                    Text("Kézi bevitel")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField(placeholderText, text: $displayDigits)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isValid ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
                        )

                    Text(meter.kind.unitSymbol)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                // Format Guidance & Live Preview
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text(formatGuidanceText)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    if let parsed = parsedDisplayValue, !displayDigits.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Normalizált állás: \(parsed) \(meter.kind.unitSymbol)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.top, 2)
                    } else if !displayDigits.isEmpty && !isValid {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Érvénytelen formátum a mérőhöz képest")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
        }
    }

    private var placeholderText: String {
        if meter.format.fractionalDigits > 0 {
            let intPart = String(repeating: "0", count: max(1, meter.format.integerDigits - 1)) + "1"
            let fracPart = String(repeating: "0", count: meter.format.fractionalDigits)
            return "\(intPart),\(fracPart)"
        } else {
            return String(repeating: "0", count: max(1, meter.format.integerDigits - 1)) + "1"
        }
    }

    private var formatGuidanceText: String {
        if meter.format.fractionalDigits > 0 {
            return "Legfeljebb \(meter.format.integerDigits) egész és \(meter.format.fractionalDigits) tizedes jegy. Vessző vagy pont használható."
        } else {
            return "Legfeljebb \(meter.format.integerDigits) egész számjegy, tizedesjegy nélkül."
        }
    }
}
