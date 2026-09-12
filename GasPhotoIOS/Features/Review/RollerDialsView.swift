import SwiftUI

struct RollerDialsView: View {
    @Binding var displayDigits: String
    var uncertainPositions: [Int] = []
    var isEditable: Bool = true

    @State private var selectedIndex: Int?

    // Parse the 8 digits from the display string (ignoring dot)
    private var digitsArray: [String] {
        let cleaned = displayDigits.replacingOccurrences(of: ".", with: "")
        let chars = Array(cleaned)
        var result = [String]()
        for i in 0..<8 {
            if i < chars.count {
                result.append(String(chars[i]))
            } else {
                result.append("0")
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                // First 5 integer digits (black rollers)
                ForEach(0..<5, id: \.self) { index in
                    digitTile(at: index, isDecimal: false)
                }

                // Decimal separator
                VStack {
                    Spacer()
                    Circle()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .padding(.bottom, 12)
                }
                .frame(width: 10, height: 64)

                // Last 3 decimal digits (red rollers)
                ForEach(5..<8, id: \.self) { index in
                    digitTile(at: index, isDecimal: true)
                }

                // Unit badge
                Text("m³")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
            )

            // Digit selector popup / keyboard helper when a dial is tapped
            if let selected = selectedIndex, isEditable {
                VStack(spacing: 8) {
                    HStack {
                        Text("\(selected + 1). görgő módosítása:")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Kész") {
                            withAnimation(.spring(response: 0.3)) {
                                selectedIndex = nil
                            }
                        }
                        .font(.footnote.weight(.semibold))
                    }

                    // Quick digit selector buttons 0..9
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0...9, id: \.self) { digit in
                                Button {
                                    setDigit(digit, at: selected)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    // Move to next digit automatically if not at end
                                    withAnimation(.spring(response: 0.3)) {
                                        if selected < 7 {
                                            selectedIndex = selected + 1
                                        } else {
                                            selectedIndex = nil
                                        }
                                    }
                                } label: {
                                    Text("\(digit)")
                                        .font(.system(.title3, design: .monospaced, weight: .bold))
                                        .frame(width: 40, height: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(digitsArray[selected] == String(digit) ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                        )
                                        .foregroundStyle(digitsArray[selected] == String(digit) ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                )
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity))
            }
        }
    }

    @ViewBuilder
    private func digitTile(at index: Int, isDecimal: Bool) -> some View {
        let digit = digitsArray[index]
        let isUncertain = uncertainPositions.contains(index)
        let isSelected = selectedIndex == index

        Button {
            guard isEditable else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if selectedIndex == index {
                    selectedIndex = nil
                } else {
                    selectedIndex = index
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                // Dial roller card
                VStack(spacing: 0) {
                    Text(digit)
                        .font(.system(size: 26, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isDecimal
                                    ? [Color(red: 0.88, green: 0.22, blue: 0.22), Color(red: 0.70, green: 0.12, blue: 0.12)]
                                    : [Color(white: 0.22), Color(white: 0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isUncertain
                                ? Color.orange
                                : (isSelected ? Color.blue : Color.white.opacity(0.18)),
                            lineWidth: isUncertain ? 2.5 : (isSelected ? 2 : 1)
                        )
                )
                .shadow(color: isUncertain ? Color.orange.opacity(0.4) : Color.clear, radius: 4)

                // Warning indicator dot if uncertain
                if isUncertain {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(index + 1). számjegy: \(digit)\(isUncertain ? ", bizonytalan" : "")")
    }

    private func setDigit(_ newDigit: Int, at index: Int) {
        var arr = digitsArray
        if index < arr.count {
            arr[index] = String(newDigit)
        }
        let intPart = arr[0..<5].joined()
        let decPart = arr[5..<8].joined()
        displayDigits = "\(intPart).\(decPart)"
    }
}
