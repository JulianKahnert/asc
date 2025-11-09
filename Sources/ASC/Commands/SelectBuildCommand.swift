//
//  SelectBuildCommand.swift
//  ASC
//
//  Created by Julian Kahnert on 09.11.25.
//

import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

struct SelectBuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "select-build",
        abstract: "Select newest build for submission"
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect")
    var appID: String

    @Argument(help: "The version string to select a build for (e.g., 1.0.0)")
    var version: String

    @Option(help: "Platform (ios or macos)")
    var platform: String = "ios"

    func run() async throws {
        // Parse platform
        let platformValue: AppStoreVersionCreateRequest.Data.Attributes.Platform
        switch platform.lowercased() {
        case "ios":
            platformValue = .iOS
        case "macos":
            platformValue = .macOS
        default:
            throw ValidationError("Invalid platform. Use 'ios' or 'macos'")
        }

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

        // Find the version ID
        print("🔍 Finding version \(version)...")
        let versionID = try await findVersion(provider: provider, appID: resolvedAppID, versionString: version, platform: platformValue)

        guard let versionID = versionID else {
            throw ValidationError("Version \(version) not found for platform \(platform)")
        }

        // Get the newest build
        print("🔍 Finding newest build for version \(version)...")
        let buildID = try await getNewestBuild(provider: provider, appID: resolvedAppID, platform: platformValue)

        guard let buildID = buildID else {
            throw ValidationError("No builds found for this app and platform")
        }

        // Assign the build to the version
        print("🔗 Assigning build to version...")
        try await assignBuildToVersion(provider: provider, versionID: versionID, buildID: buildID)

        print("✅ Successfully assigned newest build to version \(version)")
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

    private func findVersion(
        provider: APIProvider,
        appID: String,
        versionString: String,
        platform: AppStoreVersionCreateRequest.Data.Attributes.Platform
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            let endpoint: APIEndpoint<AppStoreVersionsResponse> = .appStoreVersions(
                ofAppWithId: appID,
                fields: [.appStoreVersions([.versionString, .platform])],
                limit: 50
            )

            provider.request(endpoint) { (result: Result<AppStoreVersionsResponse, Error>) in
                switch result {
                case .success(let response):
                    let matchingVersion = response.data.first {
                        $0.attributes?.versionString == versionString &&
                        $0.attributes?.platform?.rawValue == platform.rawValue
                    }

                    continuation.resume(returning: matchingVersion?.id)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func getNewestBuild(
        provider: APIProvider,
        appID: String,
        platform: AppStoreVersionCreateRequest.Data.Attributes.Platform
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            let endpoint: APIEndpoint<BuildsResponse> = .builds(
                ofAppWithId: appID,
                fields: [.builds([.version, .uploadedDate, .processingState])],
                limit: 50
            )

            provider.request(endpoint) { (result: Result<BuildsResponse, Error>) in
                switch result {
                case .success(let response):
                    // Sort builds by uploaded date to get the newest one
                    let sortedBuilds = response.data.sorted { (build1, build2) -> Bool in
                        guard let date1 = build1.attributes?.uploadedDate,
                              let date2 = build2.attributes?.uploadedDate else {
                            return false
                        }
                        return date1 > date2
                    }

                    if let build = sortedBuilds.first {
                        if let version = build.attributes?.version {
                            print("  Found build version: \(version)")
                        }
                        continuation.resume(returning: build.id)
                    } else {
                        continuation.resume(returning: nil)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func assignBuildToVersion(
        provider: APIProvider,
        versionID: String,
        buildID: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Update the app store version with the build
            let endpoint = APIEndpoint.modify(
                appStoreVersionWithId: versionID,
                buildId: buildID
            )

            provider.request(endpoint) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
