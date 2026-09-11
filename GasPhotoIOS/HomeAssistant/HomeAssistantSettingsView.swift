import SwiftUI

struct HomeAssistantSettingsView: View {
    let credentialStore: any CredentialStore
    @State private var address = "192.168.0.99:8123"
    @State private var token = ""
    @State private var statusMessage: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("Home Assistant") {
                TextField("Cím", text: $address)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .accessibilityLabel("Home Assistant címe")

                SecureField("Hosszú élettartamú hozzáférési token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Home Assistant hozzáférési token")

                Text("A token csak az iPhone biztonságos Keychain tárában marad, és nem kerül a fotónaplóba.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Kapcsolat mentése") {
                    Task { await save() }
                }
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Home Assistant")
        .task { await loadAddress() }
    }

    private func loadAddress() async {
        guard let credentials = try? await credentialStore.load() else { return }
        address = credentials.baseURL.absoluteString
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await credentialStore.save(HomeAssistantCredentials(baseURL: address, accessToken: token))
            token = ""
            statusMessage = "A kapcsolat biztonságosan mentve."
        } catch HomeAssistantCredentialsError.invalidAddress {
            statusMessage = "Adj meg egy érvényes Home Assistant címet, például: 192.168.0.99:8123"
        } catch {
            statusMessage = "A kapcsolat mentése nem sikerült."
        }
    }
}
