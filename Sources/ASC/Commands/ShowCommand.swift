//
//  ShowCommand.swift
//  ASC
//
//  Created by Julian Kahnert on 09.11.25.
//

import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

struct ShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Display current prepared version and hints for an app"
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect")
    var appID: String

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

        // Configure authentication
        let configuration = APIConfiguration(
            issuerID: issuerID,
            privateKeyID: keyID,
            privateKey: privateKey
        )

        let provider = APIProvider(configuration: configuration)

        // Check if appID is a bundle ID (contains dots) and convert to App ID if needed
        var resolvedAppID = appID
        if appID.contains(".") {
            print("🔍 Resolving bundle ID '\(appID)' to App ID...")
            resolvedAppID = try await resolveAppID(provider: provider, bundleID: appID)
        }

        // Fetch iOS version info
        print("\n📱 iOS Versions:")
        try await showVersionInfo(provider: provider, appID: resolvedAppID, platform: .iOS)

        // Fetch macOS version info
        print("\n💻 macOS Versions:")
        try await showVersionInfo(provider: provider, appID: resolvedAppID, platform: .macOS)
    }

    private func resolveAppID(provider: APIProvider, bundleID: String) async throws -> String {
        let endpoint: APIEndpoint<AppsResponse> = .apps(
            select: [.apps([.name, .bundleId])],
            filters: [.bundleId([bundleID])],
            limits: [.apps(1)]
        )

        return try await withCheckedThrowingContinuation { continuation in
            provider.request(endpoint) { (result: Result<AppsResponse, Error>) in
                switch result {
                case .success(let response):
                    guard let app = response.data.first else {
                        continuation.resume(throwing: ValidationError("No app found with bundle ID '\(bundleID)'"))
                        return
                    }
                    continuation.resume(returning: app.id)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func showVersionInfo(
        provider: APIProvider,
        appID: String,
        platform: AppStoreVersionCreateRequest.Data.Attributes.Platform
    ) async throws {
        // Get all versions for this platform
        let endpoint: APIEndpoint<AppStoreVersionsResponse> = .appStoreVersions(
            ofAppWithId: appID,
            fields: [.appStoreVersions([.versionString, .platform, .appStoreState])],
            limit: 10
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            provider.request(endpoint) { (result: Result<AppStoreVersionsResponse, Error>) in
                switch result {
                case .success(let response):
                    let versions = response.data.filter {
                        $0.attributes?.platform?.rawValue == platform.rawValue
                    }

                    if versions.isEmpty {
                        print("  No versions found")
                        continuation.resume()
                        return
                    }

                    // Process versions synchronously
                    for version in versions {
                        guard let versionString = version.attributes?.versionString,
                              let state = version.attributes?.appStoreState?.rawValue else {
                            continue
                        }

                        print("  Version: \(versionString)")
                        print("  State: \(state)")
                        print("")
                    }

                    continuation.resume()

                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func getLocalizations(
        provider: APIProvider,
        versionID: String
    ) async throws -> [(locale: String, whatsNew: String?)] {
        try await withCheckedThrowingContinuation { continuation in
            let endpoint: APIEndpoint<AppStoreVersionLocalizationsResponse> = .appStoreVersionLocalizations(
                ofAppStoreVersionWithId: versionID
            )

            provider.request(endpoint) { (result: Result<AppStoreVersionLocalizationsResponse, Error>) in
                switch result {
                case .success(let response):
                    let localizations = response.data.map { localization in
                        (
                            locale: localization.attributes?.locale ?? "",
                            whatsNew: localization.attributes?.whatsNew
                        )
                    }
                    continuation.resume(returning: localizations)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
