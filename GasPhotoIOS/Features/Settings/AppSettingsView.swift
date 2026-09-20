import SwiftUI

struct AppSettingsView: View {
    let container: AppContainer
    @Environment(\.dismiss) private var dismiss

    @State private var sampleCount: Int = 0
    @State private var activeModelVersion: String = "v1.0.0 (Gyári)"

    var body: some View {
        NavigationStack {
            List {
                // Section 1: AI Model & Training
                Section {
                    NavigationLink {
                        ModelTrainingView(
                            model: ModelTrainingViewModel(
                                trainingExampleStore: container.trainingExampleStore,
                                trainingService: container.trainingService
                            )
                        )
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.purple.gradient)
                                    .frame(width: 34, height: 34)
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 18))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Modell tanítása & AI")
                                    .font(.body.weight(.medium))
                                Text("\(activeModelVersion) • \(sampleCount) mintakép")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Mesterséges Intelligencia")
                } footer: {
                    Text("A számlálógörgők és az ablakkeret felismerésének helyi finomhangolása a saját mérőórád fotóival.")
                }

                // Section 2: Meter Catalog
                Section {
                    NavigationLink {
                        MeterListView(
                            meterRepository: container.meterRepository,
                            readingRepository: container.readingRepository
                        )
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.orange.gradient)
                                    .frame(width: 34, height: 34)
                                Image(systemName: "gauge.with.needle")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 16))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mérőórák")
                                    .font(.body.weight(.medium))
                                Text("Villany-, gáz- és vízórák kezelése")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Mérőkatalógus")
                } footer: {
                    Text("Itt vehetsz fel új mérőórákat (villany, gáz, víz), állíthatod be a számlálók formátumát vagy archiválhatod a régieket.")
                }

                // Section 3: Home Assistant Integration
                Section {
                    NavigationLink {
                        HomeAssistantSettingsView(
                            credentialStore: container.credentialStore,
                            client: container.homeAssistantClient,
                            usageSettings: container.homeAssistantUsageSettings
                        )
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.blue.gradient)
                                    .frame(width: 34, height: 34)
                                Image(systemName: "house.fill")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 16))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Home Assistant kapcsolat")
                                    .font(.body.weight(.medium))
                                Text("Szervercím és hozzáférési token")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Okosotthon Kapcsolat")
                } footer: {
                    Text("Opcionális kapcsolat. Bekapcsolva a hitelesített gázóra-leolvasások a saját Home Assistant gas_photo szolgáltatásodba szinkronizálódnak.")
                }

                // Section 3: Privacy & System Info
                Section {
                    HStack {
                        Label("Adatvédelem", systemImage: "lock.shield.fill")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("100% Helyi")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Verzió", systemImage: "info.circle")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("1.0.0 (Build 26)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Névjegy & Biztonság")
                } footer: {
                    Text("A fotók és leolvasások a telefon védett helyi tárhelyén, a Home Assistant hozzáférési token a Keychainben tárolódik. Bekapcsolt szinkronizáció esetén az adatok a saját Home Assistant szerveredre távoznak.")
                }
            }
            .navigationTitle("Beállítások")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kész") { dismiss() }
                }
            }
            .task {
                sampleCount = (try? await container.trainingExampleStore.count()) ?? 0
                let status = await container.trainingService.activeStatus(for: .digitClassifier)
                activeModelVersion = status.version
            }
        }
    }
}
