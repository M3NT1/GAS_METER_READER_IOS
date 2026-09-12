import SwiftUI

struct HomeAssistantSettingsView: View {
    let credentialStore: any CredentialStore
    var client: any HomeAssistantClient = URLSessionHomeAssistantClient()

    @State private var address = "192.168.0.99:8123"
    @State private var token = ""
    @State private var storedToken = ""
    @State private var hasStoredCredentials = false
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var testResult: ConnectionTestResult?
    @State private var saveStatusMessage: String?

    private var effectiveToken: String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? storedToken : trimmed
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "network")
                        .foregroundStyle(Color.accentColor)
                    TextField("Cím (pl. 192.168.0.99:8123)", text: $address)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .accessibilityLabel("Home Assistant címe")
                }

                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(Color.accentColor)
                    SecureField(
                        hasStoredCredentials ? "Új token megadása (elhagyható)" : "Hosszú élettartamú token",
                        text: $token
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Home Assistant hozzáférési token")
                }

                if hasStoredCredentials {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Text("Érvényes token elmentve a Keychainben.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Kiszolgáló beállítása", systemImage: "server.rack")
            } footer: {
                Label("A token kizárólag az iPhone biztonságos Keychain tárában marad, és közvetlenül a Home Assistant REST API-val kommunikál.", systemImage: "lock.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Kapcsolat tesztelése...")
                        } else {
                            Label("Kapcsolat tesztelése", systemImage: "antenna.radiowaves.left.and.right")
                                .fontWeight(.medium)
                        }
                        Spacer()
                    }
                }
                .disabled(effectiveToken.isEmpty || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting || isSaving)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Mentés folyamatban...")
                        } else {
                            Label("Kapcsolat mentése", systemImage: "tray.and.arrow.down.fill")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(effectiveToken.isEmpty || isSaving || isTesting)
            }

            if let testResult {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: testResult.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(testResult.isSuccess ? Color.green : Color.red)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(testResult.isSuccess ? "Kapcsolat sikeres" : "Kapcsolati hiba")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(testResult.isSuccess ? Color.primary : Color.red)

                            Text(testResult.message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Teszt eredménye")
                }
            }

            if let saveStatusMessage {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(saveStatusMessage)
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Home Assistant")
        .task { await loadCredentials() }
    }

    private func loadCredentials() async {
        guard let credentials = try? await credentialStore.load() else { return }
        address = credentials.baseURL.absoluteString
        storedToken = credentials.accessToken
        hasStoredCredentials = true
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        do {
            let tokenToTest = effectiveToken
            let creds = try HomeAssistantCredentials(baseURL: address, accessToken: tokenToTest)
            let result = try await client.testConnection(credentials: creds)
            testResult = result
        } catch HomeAssistantCredentialsError.invalidAddress {
            testResult = ConnectionTestResult(
                isSuccess: false,
                message: "A megadott cím formátuma érvénytelen (pl. 192.168.0.99:8123 szükséges)."
            )
        } catch {
            testResult = ConnectionTestResult(
                isSuccess: false,
                message: "Tesztelés sikertelen: \(error.localizedDescription)"
            )
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let tokenToSave = effectiveToken
            let creds = try HomeAssistantCredentials(baseURL: address, accessToken: tokenToSave)
            try await credentialStore.save(creds)
            storedToken = tokenToSave
            hasStoredCredentials = true
            token = ""
            saveStatusMessage = "A kapcsolat biztonságosan mentve."
        } catch HomeAssistantCredentialsError.invalidAddress {
            saveStatusMessage = "Adj meg egy érvényes Home Assistant címet, például: 192.168.0.99:8123"
        } catch {
            saveStatusMessage = "A kapcsolat mentése nem sikerült: \(error.localizedDescription)"
        }
    }
}
