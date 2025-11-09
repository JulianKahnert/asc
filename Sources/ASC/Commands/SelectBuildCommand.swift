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
        let platforms: [(name: String, value: Platform)]
        switch platform.lowercased() {
        case "ios":
            platforms = [("iOS", .ios)]
        case "macos":
            platforms = [("macOS", .macOs)]
        case "both":
            platforms = [("iOS", .ios), ("macOS", .macOs)]
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
        platform: Platform
    ) async throws -> String? {
        var parameters = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters()
        parameters.fieldsAppStoreVersions = [.versionString, .platform, .appStoreState]
        parameters.limit = 50

        let request = APIEndpoint.v1.apps.id(appID).appStoreVersions.get(parameters: parameters)
        let response = try await provider.request(request)

        // Filter matching versions
        let matchingVersions = response.data.filter {
            $0.attributes?.versionString == versionString &&
            $0.attributes?.platform?.rawValue == platform.rawValue
        }

        // Prioritize by state: active states first
        let priorityStates = [
            "PREPARE_FOR_SUBMISSION",
            "WAITING_FOR_REVIEW",
            "IN_REVIEW",
            "PENDING_DEVELOPER_RELEASE",
            "DEVELOPER_REJECTED",
            "REJECTED"
        ]

        // Find version with highest priority state
        for state in priorityStates {
            if let version = matchingVersions.first(where: {
                $0.attributes?.appStoreState?.rawValue == state
            }) {
                return version.id
            }
        }

        // Fallback: return first matching version (e.g., READY_FOR_SALE)
        return matchingVersions.first?.id
    }

    private func getNewestBuild(
        provider: APIProvider,
        appID: String,
        platform: Platform
    ) async throws -> String? {
        // Map platform to API filter enum
        let platformFilter: [APIEndpoint.V1.Builds.GetParameters.FilterPreReleaseVersionPlatform]
        switch platform {
        case .ios:
            platformFilter = [.ios]
        case .macOs:
            platformFilter = [.macOs]
        default:
            fatalError("Unexpected platform: \(platform). Should be validated earlier.")
        }

        var parameters = APIEndpoint.V1.Builds.GetParameters()
        parameters.filterApp = [appID]
        parameters.filterPreReleaseVersionPlatform = platformFilter
        parameters.sort = [.minusuploadedDate]

        let request = APIEndpoint.v1.builds.get(parameters: parameters)
        let response = try await provider.request(request)

        if let build = response.data.first {
            if let version = build.attributes?.version {
                print("  Found build version: \(version) for platform: \(platform)")
            }
            return build.id
        } else {
            return nil
        }
    }

    private func assignBuildToVersion(
        provider: APIProvider,
        versionID: String,
        buildID: String
    ) async throws {
        // Create the request body to update the app store version with the build
        let updateRequest = AppStoreVersionUpdateRequest(
            data: .init(
                type: .appStoreVersions,
                id: versionID,
                relationships: .init(
                    build: .init(
                        data: .init(
                            type: .builds,
                            id: buildID
                        )
                    )
                )
            )
        )

        let request = APIEndpoint.v1.appStoreVersions.id(versionID).patch(updateRequest)
        _ = try await provider.request(request)
    }
}
