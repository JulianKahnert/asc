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

    @Option(help: "Platform (ios, macos, or both)")
    var platform: String = "both"

    func run() async throws {
        // Determine which platforms to process
        let platforms: [(name: String, value: AppStoreVersionCreateRequest.Data.Attributes.Platform)]
        switch platform.lowercased() {
        case "ios":
            platforms = [("iOS", .iOS)]
        case "macos":
            platforms = [("macOS", .macOS)]
        case "both":
            platforms = [("iOS", .iOS), ("macOS", .macOS)]
        default:
            throw ValidationError("Invalid platform. Use 'ios', 'macos', or 'both'")
        }

        let provider = try KeychainHelper.createAPIProvider()

        // Check if appID is a bundle ID (contains dots) and convert to App ID if needed
        var resolvedAppID = appID
        if appID.contains(".") {
            print("🔍 Resolving bundle ID '\(appID)' to App ID...")
            resolvedAppID = try await KeychainHelper.resolveAppID(provider: provider, bundleID: appID)
        }

        // Process each platform
        for (platformName, platformValue) in platforms {
            print("\n📱 Processing \(platformName)...")

            // Find the version ID
            print("🔍 Finding version \(version)...")
            guard let versionID = try await findVersion(provider: provider, appID: resolvedAppID, versionString: version, platform: platformValue) else {
                print("⚠️  Version \(version) not found for platform \(platformName)")
                continue
            }

            // Get the newest build
            print("🔍 Finding newest build for \(platformName)...")
            guard let buildID = try await getNewestBuild(provider: provider, appID: resolvedAppID, platform: platformValue) else {
                print("⚠️  No builds found for this app and platform \(platformName)")
                continue
            }

            // Assign the build to the version
            print("🔗 Assigning build to version...")
            try await assignBuildToVersion(provider: provider, versionID: versionID, buildID: buildID)

            print("✅ Successfully assigned newest build to version \(version) for \(platformName)")
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
            // Map platform to API filter enum
            let platformFilter: [ListBuilds.Filter.PreReleaseVersionPlatform]
            switch platform {
            case .iOS:
                platformFilter = [.IOS]
            case .macOS:
                platformFilter = [.MAC_OS]
            default:
                fatalError("Unexpected platform: \(platform). Should be validated earlier.")
            }

            let endpoint: APIEndpoint<BuildsResponse> = .builds(
                filter: [
                    .app([appID]),
                    .preReleaseVersionPlatform(platformFilter)
                ],
                sort: [.uploadedDateDescending]
            )

            provider.request(endpoint) { (result: Result<BuildsResponse, Error>) in
                switch result {
                case .success(let response):
                    if let build = response.data.first {
                        if let version = build.attributes?.version {
                            print("  Found build version: \(version) for platform: \(platform)")
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
