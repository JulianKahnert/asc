import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation
import Security

enum KeychainHelper {
    static let service = "de.JulianKahnert.asc"

    // MARK: - Keychain Operations

    static func addKeychainItem(service: String, account: String, data: String) -> Bool {
        guard let data = data.data(using: .utf8) else { return false }

        // Try with iCloud sync first
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true
        ]

        // Delete existing item with sync enabled
        SecItemDelete(query as CFDictionary)
        var status = SecItemAdd(query as CFDictionary, nil)

        // If iCloud sync failed, try without sync (local only)
        if status != errSecSuccess {
            print("⚠️  iCloud Keychain sync not available, storing credentials locally only")

            // Update query to store locally
            query[kSecAttrSynchronizable as String] = false

            // Delete existing local item if any
            SecItemDelete(query as CFDictionary)
            status = SecItemAdd(query as CFDictionary, nil)
        }

        return status == errSecSuccess
    }

    static func getKeychainItem(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    static func deleteKeychainItem(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func createAPIProvider() throws -> APIProvider {
        guard let keyID = getKeychainItem(service: service, account: "keyID") else {
            throw ValidationError("keyID not found in keychain. Please run 'asc init' first.")
        }

        guard let privateKey = getKeychainItem(service: service, account: "privateKey") else {
            throw ValidationError("privateKey not found in keychain. Please run 'asc init' first.")
        }

        // Check if issuerID exists to determine which authentication mode to use
        let issuerID = getKeychainItem(service: service, account: "issuerID")

        let configuration: APIConfiguration
        if let issuerID = issuerID {
            // Team API Key mode (with issuerID)
            configuration = try APIConfiguration(
                issuerID: issuerID,
                privateKeyID: keyID,
                privateKey: privateKey
            )
        } else {
            // Individual API Key mode (without issuerID)
            configuration = try APIConfiguration(
                individualPrivateKeyID: keyID,
                individualPrivateKey: privateKey
            )
        }

        return APIProvider(configuration: configuration)
    }

    // MARK: - App ID Resolution

    /// Resolves an App ID or Bundle ID string to a numeric App ID.
    ///
    /// If the input contains a dot (e.g. "com.example.app"), it is treated as a
    /// Bundle ID and resolved via the API. Otherwise it is returned as-is.
    static func resolveAppID(provider: APIProvider, appIDOrBundleID input: String) async throws -> String {
        guard input.contains(".") else { return input }

        print("🔍 Resolving bundle ID '\(input)' to App ID...")

        var parameters = APIEndpoint.V1.Apps.GetParameters()
        parameters.fieldsApps = [.name, .bundleID]
        parameters.filterBundleID = [input]
        parameters.limit = 1

        let request = APIEndpoint.v1.apps.get(parameters: parameters)
        let response = try await provider.request(request)

        guard let app = response.data.first else {
            throw ValidationError("No app found with bundle ID '\(input)'")
        }
        return app.id
    }

    // MARK: - Xcode Cloud

    /// Returns the Xcode Cloud CI Product ID for a given App ID.
    static func getCiProductID(provider: APIProvider, appID: String) async throws -> String {
        let request = APIEndpoint.v1.apps.id(appID).ciProduct.get()
        let response = try await provider.request(request)
        return response.data.id
    }
}
