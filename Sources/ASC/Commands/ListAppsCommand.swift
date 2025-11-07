//
//  ListAppsCommand.swift
//  ASC
//
//  Created by Julian Kahnert on 07.11.25.
//

import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

struct ListAppsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-apps",
        abstract: "List all apps in your App Store Connect account"
    )

    func run() async throws {
        // Retrieve credentials from keychain
        let service = KeychainHelper.service

        guard let issuerID = KeychainHelper.getKeychainItem(service: service, account: "issuerID") else {
            throw ValidationError("issuerID not found in keychain. Please run 'asc init' first.")
        }

        guard let keyID = KeychainHelper.getKeychainItem(service: service, account: "keyID") else {
            throw ValidationError("keyID not found in keychain. Please run 'asc init' first.")
        }

        guard let privateKey = KeychainHelper.getKeychainItem(service: service, account: "privateKey") else {
            throw ValidationError("privateKey not found in keychain. Please run 'asc init' first.")
        }

        print("🔑 Retrieved credentials from keychain")

        // Configure authentication
        let configuration = APIConfiguration(
            issuerID: issuerID,
            privateKeyID: keyID,
            privateKey: privateKey
        )

        let provider = APIProvider(configuration: configuration)

        print("📱 Fetching apps from App Store Connect...\n")

        do {
            let apps = try await listApps(provider: provider)

            if apps.isEmpty {
                print("No apps found in your account.")
            } else {
                print("Found \(apps.count) app(s):\n")
                for app in apps {
                    print("📦 \(app.name)")
                    print("   App ID: \(app.id)")
                    print("   Bundle ID: \(app.bundleID)")
                    print("")
                }
            }
        } catch {
            print("❌ Error: \(error)")
            throw error
        }
    }

    private func listApps(provider: APIProvider) async throws -> [(id: String, name: String, bundleID: String)] {
        try await withCheckedThrowingContinuation { continuation in
            let endpoint: APIEndpoint<AppsResponse> = .apps(
                select: [.apps([.name, .bundleId])],
                limits: [.apps(200)]
            )

            provider.request(endpoint) { (result: Result<AppsResponse, Error>) in
                switch result {
                case .success(let response):
                    let apps = response.data.map { app in
                        (
                            id: app.id,
                            name: app.attributes?.name ?? "Unknown",
                            bundleID: app.attributes?.bundleId ?? "Unknown"
                        )
                    }
                    continuation.resume(returning: apps)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
