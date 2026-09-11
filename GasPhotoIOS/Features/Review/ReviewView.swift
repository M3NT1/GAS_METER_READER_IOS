import SwiftUI
import UIKit

struct ReviewView: View {
    @Bindable var model: ReviewViewModel
    let photoURL: URL?
    @State private var displayDigits: String
    @State private var window: NormalizedRect?

    init(model: ReviewViewModel, photoURL: URL?) {
        self.model = model
        self.photoURL = photoURL
        _displayDigits = State(initialValue: model.reading.approvedDigits ?? Self.formattedProposal(model.reading.proposal?.digits))
        _window = State(initialValue: model.reading.window)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photoPreview

                VStack(alignment: .leading, spacing: 8) {
                    Text("Leolvasott érték")
                        .font(.headline)
                    TextField("00000.000", text: $displayDigits)
                        .font(.system(.title2, design: .monospaced))
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Gázóra számláló értéke")
                    HStack(spacing: 0) {
                        Text("Az első öt számjegy fekete, az utolsó három")
                        Text(" piros.").foregroundStyle(.red)
                    }
                    .font(.footnote)
                }

                if let proposal = model.reading.proposal, !proposal.uncertainPositions.isEmpty {
                    Label("A jelzett számjegyek bizonytalanok; ellenőrizd és javítsd őket.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }

                LabeledContent("Készítés ideje", value: model.reading.capturedAt.formatted(date: .numeric, time: .standard))
                LabeledContent("Felismerés", value: model.reading.proposal == nil ? "Nincs javaslat" : "Helyben futó modell")

                if let lastError = model.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Button("Ellenőriztem, mentés") {
                    Task { await model.approve(displayDigits: displayDigits) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canApprove(displayDigits: displayDigits))
                .accessibilityHint("Csak ellenőrzés után menti a leolvasást feltöltésre váró állapotba.")
            }
            .padding()
        }
        .navigationTitle("Gázóra ellenőrzése")
    }

    @ViewBuilder
    private var photoPreview: some View {
        ZStack {
            if let photoURL, let image = UIImage(contentsOfFile: photoURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ContentUnavailableView("Nincs fotó", systemImage: "camera")
                    .frame(height: 280)
            }
            WindowEditorView(window: $window)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Az eredeti gázóra-fotó a felismerési kerettel")
    }

    private static func formattedProposal(_ digits: String?) -> String {
        guard let digits, digits.count == 8 else { return "" }
        let index = digits.index(digits.startIndex, offsetBy: 5)
        return String(digits[..<index]) + "." + String(digits[index...])
    }
}
