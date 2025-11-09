//
//  SubmitCommand.swift
//  ASC
//
//  Created by Julian Kahnert on 09.11.25.
//

import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

struct SubmitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit",
        abstract: "Submit version for Apple review"
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect")
    var appID: String

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

            // Find the version ready for submission
            print("🔍 Finding version in PREPARE_FOR_SUBMISSION state...")
            guard let (versionID, versionString) = try await findPreparedVersion(
                provider: provider,
                appID: resolvedAppID,
                platform: platformValue
            ) else {
                print("⚠️  No version found in PREPARE_FOR_SUBMISSION state for \(platformName)")
                continue
            }

            print("  Found version: \(versionString) (ID: \(versionID))")

            // Submit version for review
            print("📤 Submitting version \(versionString) for review...")
            do {
                try await submitVersion(provider: provider, appID: resolvedAppID, platform: platformValue, versionID: versionID)
                print("✅ Successfully submitted \(platformName) version \(versionString) for review")
            } catch {
                let errorString = String(describing: error)
                if errorString.contains("build") || errorString.contains("BUILD") {
                    print("❌ Error: No build assigned to version \(versionString)")
                    print("   Please run: asc select-build \(appID) \(versionString) --platform \(platform.lowercased())")
                } else {
                    print("❌ Error submitting version: \(error)")
                }
            }
        }
    }

    private func findPreparedVersion(
        provider: APIProvider,
        appID: String,
        platform: Platform
    ) async throws -> (id: String, versionString: String)? {
        var parameters = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters()
        parameters.fieldsAppStoreVersions = [.versionString, .platform, .appStoreState]

        // Map Platform to FilterPlatform
        let filterPlatform: APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters.FilterPlatform
        switch platform {
        case .ios:
            filterPlatform = .ios
        case .macOs:
            filterPlatform = .macOs
        case .tvOs:
            filterPlatform = .tvOs
        case .visionOs:
            filterPlatform = .visionOs
        }

        parameters.filterPlatform = [filterPlatform]
        parameters.filterAppStoreState = [.prepareForSubmission]
        parameters.limit = 10

        let request = APIEndpoint.v1.apps.id(appID).appStoreVersions.get(parameters: parameters)
        let response = try await provider.request(request)

        if let version = response.data.first,
           let versionString = version.attributes?.versionString {
            return (id: version.id, versionString: versionString)
        } else {
            return nil
        }
    }

    private func submitVersion(
        provider: APIProvider,
        appID: String,
        platform: Platform,
        versionID: String
    ) async throws {
        // Step 1: Create ReviewSubmission (container for app/platform)
        let reviewSubmissionRequest = ReviewSubmissionCreateRequest(
            data: .init(
                type: .reviewSubmissions,
                attributes: .init(platform: platform),
                relationships: .init(
                    app: .init(
                        data: .init(
                            type: .apps,
                            id: appID
                        )
                    )
                )
            )
        )

        let createRequest = APIEndpoint.v1.reviewSubmissions.post(reviewSubmissionRequest)
        let reviewSubmissionResponse = try await provider.request(createRequest)
        let reviewSubmissionID = reviewSubmissionResponse.data.id

        print("  Created review submission with ID: \(reviewSubmissionID)")

        // Step 2: Add ReviewSubmissionItem (the actual version to be reviewed)
        let itemRequest = ReviewSubmissionItemCreateRequest(
            data: .init(
                type: .reviewSubmissionItems,
                relationships: .init(
                    reviewSubmission: .init(
                        data: .init(
                            type: .reviewSubmissions,
                            id: reviewSubmissionID
                        )
                    ),
                    appStoreVersion: .init(
                        data: .init(
                            type: .appStoreVersions,
                            id: versionID
                        )
                    )
                )
            )
        )

        let addItemRequest = APIEndpoint.v1.reviewSubmissionItems.post(itemRequest)
        _ = try await provider.request(addItemRequest)
    }
}
