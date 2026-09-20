import SwiftUI

struct HomeAssistantSetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Header badge
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hivatalos integrációs útmutató")
                                .font(.subheadline.weight(.semibold))
                            Text("Utolsó ellenőrzés dátuma: \(HomeAssistantSetupGuide.lastVerified)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Sections
                ForEach(HomeAssistantSetupGuide.sections) { section in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.summary)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)

                            ForEach(section.details, id: \.self) { detail in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let snippet = section.codeSnippet {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Példa konfiguráció:")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Text(snippet)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .padding(.top, 4)
                            }

                            if !section.links.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(section.links) { link in
                                        Link(destination: link.url) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.up.right.square")
                                                    .font(.caption)
                                                Text(link.title)
                                                    .font(.caption.weight(.medium))
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text(section.title)
                    }
                }
            }
            .navigationTitle("Home Assistant Útmutató")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bezárás") { dismiss() }
                }
            }
        }
    }
}
