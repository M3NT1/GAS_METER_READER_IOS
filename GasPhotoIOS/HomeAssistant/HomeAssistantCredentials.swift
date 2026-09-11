import Foundation
import Security

struct HomeAssistantCredentials: Codable, Equatable, Sendable {
    let baseURL: URL
    let accessToken: String

    init(baseURL: String, accessToken: String) throws {
        let trimmedAddress = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = trimmedAddress.contains("://") ? trimmedAddress : "http://\(trimmedAddress)"
        guard let url = URL(string: address),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw HomeAssistantCredentialsError.invalidAddress
        }

        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw HomeAssistantCredentialsError.missingAccessToken
        }

        self.baseURL = url
        self.accessToken = trimmedToken
    }
}

enum HomeAssistantCredentialsError: Error, Equatable {
    case invalidAddress
    case missingAccessToken
}

protocol CredentialStore: Sendable {
    func save(_ credentials: HomeAssistantCredentials) async throws
    func load() async throws -> HomeAssistantCredentials?
    func clear() async throws
}

enum CredentialStoreError: Error, Equatable {
    case keychainFailure(OSStatus)
    case unreadableCredentials
}

actor KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account = "home-assistant"

    init(service: String = "hu.m3nt1.gasphoto.home-assistant") {
        self.service = service
    }

    func save(_ credentials: HomeAssistantCredentials) throws {
        let encoded = try JSONEncoder().encode(credentials)
        let match: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: encoded,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychainFailure(updateStatus)
        }

        var add = match
        attributes.forEach { add[$0.key] = $0.value }
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychainFailure(addStatus)
        }
    }

    func load() throws -> HomeAssistantCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialStoreError.keychainFailure(status)
        }
        guard let credentials = try? JSONDecoder().decode(HomeAssistantCredentials.self, from: data) else {
            throw CredentialStoreError.unreadableCredentials
        }
        return credentials
    }

    func clear() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainFailure(status)
        }
    }
}
