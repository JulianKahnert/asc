//
//  KeychainHelper.swift
//  ASC
//
//  Created by Julian Kahnert on 07.11.25.
//

import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation
import Security

enum KeychainHelper {
    static let service = "de.JulianKahnert.asc"

    static func addKeychainItem(service: String, account: String, data: String) -> Bool {
        let data = data.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        // Lösche das bestehende Element, falls es existiert
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func getKeychainItem(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
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
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func createAPIProvider() throws -> APIProvider {
        guard let issuerID = getKeychainItem(service: service, account: "issuerID") else {
            throw ValidationError("issuerID not found in keychain. Please run 'asc init' first.")
        }

        guard let keyID = getKeychainItem(service: service, account: "keyID") else {
            throw ValidationError("keyID not found in keychain. Please run 'asc init' first.")
        }

        guard let privateKey = getKeychainItem(service: service, account: "privateKey") else {
            throw ValidationError("privateKey not found in keychain. Please run 'asc init' first.")
        }

        let configuration = try APIConfiguration(
            issuerID: issuerID,
            privateKeyID: keyID,
            privateKey: privateKey
        )

        return APIProvider(configuration: configuration)
    }

    static func resolveAppID(provider: APIProvider, bundleID: String) async throws -> String {
        var parameters = APIEndpoint.V1.Apps.GetParameters()
        parameters.fieldsApps = [.name, .bundleID]
        parameters.filterBundleID = [bundleID]
        parameters.limit = 1

        let request = APIEndpoint.v1.apps.get(parameters: parameters)
        let response = try await provider.request(request)

        guard let app = response.data.first else {
            throw ValidationError("No app found with bundle ID '\(bundleID)'")
        }
        return app.id
    }
}
