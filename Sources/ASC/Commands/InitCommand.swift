//
//  InitCommand.swift
//  ASC
//
//  Created by Julian Kahnert on 07.11.25.
//

import ArgumentParser
import Foundation

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize App Store Connect credentials"
    )

    @Option(name: .customLong("issuerID"), help: "The issuer ID from App Store Connect")
    var issuerID: String

    @Option(name: .customLong("keyID"), help: "The key ID from App Store Connect")
    var keyID: String

    @Option(name: .customLong("privateKeyFile"), help: "Path to the private key file (.p8)")
    var privateKeyFile: String

    func run() async throws {
        // Read the private key from file
        let privateKeyURL = URL(fileURLWithPath: privateKeyFile)
        guard FileManager.default.fileExists(atPath: privateKeyFile) else {
            throw ValidationError("Private key file not found at: \(privateKeyFile)")
        }

        let privateKeyContent = try String(contentsOf: privateKeyURL, encoding: .utf8)

        // Strip the PEM headers/footers - SDK expects only the base64 content
        let privateKey = privateKeyContent
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Store credentials in keychain
        let service = KeychainHelper.service

        guard KeychainHelper.addKeychainItem(service: service, account: "issuerID", data: issuerID) else {
            throw ValidationError("Failed to store issuerID in keychain")
        }

        guard KeychainHelper.addKeychainItem(service: service, account: "keyID", data: keyID) else {
            throw ValidationError("Failed to store keyID in keychain")
        }

        guard KeychainHelper.addKeychainItem(service: service, account: "privateKey", data: privateKey) else {
            throw ValidationError("Failed to store privateKey in keychain")
        }

        print("✅ Credentials successfully stored in keychain")
    }
}
