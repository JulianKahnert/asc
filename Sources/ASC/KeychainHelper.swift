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
