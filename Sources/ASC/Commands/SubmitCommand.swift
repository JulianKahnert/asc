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

        // Collect all versions to submit
        var versionsToSubmit: [(platformName: String, platform: Platform, versionID: String, versionString: String)] = []

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
            versionsToSubmit.append((platformName, platformValue, versionID, versionString))
        }

        // If no versions found, exit
        guard !versionsToSubmit.isEmpty else {
            print("\n❌ No versions ready for submission")
            return
        }

        // Submit all versions in one ReviewSubmission
        print("\n📤 Creating review submission for \(versionsToSubmit.count) version(s)...")
        do {
            try await submitVersions(provider: provider, appID: resolvedAppID, versions: versionsToSubmit)
            print("\n✅ Successfully submitted for review:")
            for version in versionsToSubmit {
                print("   • \(version.platformName): \(version.versionString)")
            }
        } catch {
            let errorString = String(describing: error)
            if errorString.contains("build") || errorString.contains("BUILD") {
                print("❌ Error: Build missing for one or more versions")
                for version in versionsToSubmit {
                    print("   Check: asc select-build \(appID) \(version.versionString) --platform \(version.platformName.lowercased())")
                }
            } else {
                print("❌ Error submitting versions: \(error)")
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

    private func submitVersions(
        provider: APIProvider,
        appID: String,
        versions: [(platformName: String, platform: Platform, versionID: String, versionString: String)]
    ) async throws {
        // Apple's ReviewSubmission rules:
        // - One ReviewSubmission can only contain ONE app store version
        // - Must specify platform attribute
        // - Create separate ReviewSubmissions for each platform

        for version in versions {
            print("  Processing \(version.platformName) version \(version.versionString)...")

            // Check if ReviewSubmission already exists for this platform
            let reviewSubmissionID: String

            if let existingID = try await findExistingReviewSubmission(
                provider: provider,
                appID: appID,
                platform: version.platform
            ) {
                print("    Found existing review submission with ID: \(existingID)")
                reviewSubmissionID = existingID
            } else {
                // Create ReviewSubmission for this platform
                let reviewSubmissionRequest = ReviewSubmissionCreateRequest(
                    data: .init(
                        type: .reviewSubmissions,
                        attributes: .init(platform: version.platform),
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
                reviewSubmissionID = reviewSubmissionResponse.data.id
                print("    Created review submission with ID: \(reviewSubmissionID)")
            }

            // Add the version as ReviewSubmissionItem
            print("    Adding version as review item...")
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
                                id: version.versionID
                            )
                        )
                    )
                )
            )

            let addItemRequest = APIEndpoint.v1.reviewSubmissionItems.post(itemRequest)
            _ = try await provider.request(addItemRequest)
        }
    }

    private func findExistingReviewSubmission(
        provider: APIProvider,
        appID: String,
        platform: Platform
    ) async throws -> String? {
        // Map Platform to FilterPlatform
        let filterPlatform: APIEndpoint.V1.ReviewSubmissions.GetParameters.FilterPlatform
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

        // Look for existing review submissions for this app and platform
        var parameters = APIEndpoint.V1.ReviewSubmissions.GetParameters(filterApp: [appID])
        parameters.filterPlatform = [filterPlatform]
        parameters.filterState = [.readyForReview, .waitingForReview, .inReview]
        parameters.limit = 1

        let request = APIEndpoint.v1.reviewSubmissions.get(parameters: parameters)
        let response = try await provider.request(request)

        return response.data.first?.id
    }
}
