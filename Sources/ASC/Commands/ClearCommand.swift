//
//  ClearCommand.swift
//  ASC
//
//  Created by Julian Kahnert on 07.11.25.
//

import ArgumentParser
import Foundation

struct ClearCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Remove all stored credentials from keychain"
    )

    func run() async throws {
        let service = KeychainHelper.service
        let accounts = ["issuerID", "keyID", "privateKey"]

        print("🗑️  Removing stored credentials from keychain...")

        var allSuccessful = true
        for account in accounts {
            if !KeychainHelper.deleteKeychainItem(service: service, account: account) {
                print("⚠️  Warning: Could not remove \(account) from keychain")
                allSuccessful = false
            }
        }

        if allSuccessful {
            print("✅ All credentials successfully removed from keychain")
        } else {
            throw ValidationError("Failed to remove some credentials from keychain")
        }
    }
}
