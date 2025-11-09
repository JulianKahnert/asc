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
        // Note: The SDK doesn't support the 'include' parameter for the list endpoint,
        // but the API does support it. We need to make individual requests for each version
        // to get build information. For now, we'll fetch builds separately.

        // First, get all versions
        let endpoint: APIEndpoint<AppStoreVersionsResponse> = .appStoreVersions(
            ofAppWithId: appID,
            fields: [.appStoreVersions([.versionString, .platform, .appStoreState])],
            limit: 10
        )

        let versionData: [(id: String, versionString: String, state: String)] = try await withCheckedThrowingContinuation { continuation in
            provider.request(endpoint) { (result: Result<AppStoreVersionsResponse, Error>) in
                switch result {
                case .success(let response):
                    let filteredVersions = response.data.filter {
                        $0.attributes?.platform?.rawValue == platform.rawValue
                    }

                    let data = filteredVersions.compactMap { version -> (String, String, String)? in
                        guard let versionString = version.attributes?.versionString,
                              let state = version.attributes?.appStoreState?.rawValue else {
                            return nil
                        }
                        return (version.id, versionString, state)
                    }

                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        if versionData.isEmpty {
            print("  No versions found")
            return
        }

        // Now get all builds for this app and platform to match them
        let buildMap = try await getBuildsMap(provider: provider, appID: appID, platform: platform)

        // Process each version
        for (versionID, versionString, state) in versionData {
            print("  Version: \(versionString)")
            print("  State: \(state)")

            // Check if there's a build assigned by looking at builds with matching appStoreVersion
            if let buildNumber = buildMap[versionID] {
                print("  Build: \(buildNumber)")
            } else {
                print("  Build: Not selected")
            }
            print("")
        }
    }

    private func getBuildsMap(
        provider: APIProvider,
        appID: String,
        platform: AppStoreVersionCreateRequest.Data.Attributes.Platform
    ) async throws -> [String: String] {
        // TODO: Implement once SDK supports Build.appStoreVersion relationship
        // See SDK_LIMITATIONS.md for details on required SDK changes
        return [:]
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
