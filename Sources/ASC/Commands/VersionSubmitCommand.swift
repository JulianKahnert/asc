import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

/// Submits a prepared version for Apple review.
struct VersionSubmitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit",
        abstract: "Submit version for Apple review.",
        discussion: """
            Examples:
              $ asc versions submit com.example.app
              $ asc versions submit com.example.app --platform ios
            """
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect.")
    var appID: String

    @Option(help: "Platform (ios, macos, or both).")
    var platform: String = "both"

    func run() async throws {
        let platforms: [Platform]
        switch platform.lowercased() {
        case "ios":
            platforms = [.ios]
        case "macos":
            platforms = [.macOs]
        case "both":
            platforms = [.ios, .macOs]
        default:
            throw ValidationError("Invalid platform. Use 'ios', 'macos', or 'both'")
        }

        let provider = try KeychainHelper.createAPIProvider()
        let resolvedAppID = try await KeychainHelper.resolveAppID(provider: provider, appIDOrBundleID: appID)

        try await Self.execute(
            provider: provider,
            appID: resolvedAppID,
            appIDDisplay: appID,
            platforms: platforms
        )
    }

    static func execute(
        provider: APIProvider,
        appID: String,
        appIDDisplay: String,
        platforms: [Platform]
    ) async throws {
        var versionsToSubmit: [(platform: Platform, versionID: String, versionString: String)] = []

        for platform in platforms {
            print("\n📱 Processing \(platform.name)...")

            print("🔍 Finding version in PREPARE_FOR_SUBMISSION state...")
            guard let (versionID, versionString) = try await findPreparedVersion(
                provider: provider,
                appID: appID,
                platform: platform
            ) else {
                print("⚠️  No version found in PREPARE_FOR_SUBMISSION state for \(platform.name)")
                continue
            }

            print("  Found version: \(versionString) (ID: \(versionID))")
            versionsToSubmit.append((platform, versionID, versionString))
        }

        guard !versionsToSubmit.isEmpty else {
            print("\n❌ No versions ready for submission")
            return
        }

        print("\n📤 Creating review submission for \(versionsToSubmit.count) version(s)...")
        do {
            try await submitVersions(provider: provider, appID: appID, versions: versionsToSubmit)
            print("\n✅ Successfully submitted for review:")
            for version in versionsToSubmit {
                print("   \(version.platform.name): \(version.versionString)")
            }
        } catch {
            let errorString = String(describing: error)
            if errorString.contains("build") || errorString.contains("BUILD") {
                print("❌ Error: Build missing for one or more versions")
                for version in versionsToSubmit {
                    print("   Check: asc versions select-build \(appIDDisplay) \(version.versionString) --platform \(version.platform.name.lowercased())")
                }
            } else {
                print("❌ Error submitting versions: \(error)")
            }
        }
    }

    static func findPreparedVersion(
        provider: APIProvider,
        appID: String,
        platform: Platform
    ) async throws -> (id: String, versionString: String)? {
        var parameters = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters()
        parameters.fieldsAppStoreVersions = [.versionString, .platform, .appStoreState]

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

    static func submitVersions(
        provider: APIProvider,
        appID: String,
        versions: [(platform: Platform, versionID: String, versionString: String)]
    ) async throws {
        for version in versions {
            print("  Processing \(version.platform.name) version \(version.versionString)...")

            let reviewSubmissionID: String

            if let existingID = try await findExistingReviewSubmission(
                provider: provider,
                appID: appID,
                platform: version.platform
            ) {
                print("    Found existing review submission with ID: \(existingID)")
                reviewSubmissionID = existingID
            } else {
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

            print("    Submitting review submission for review...")
            try await submitReviewSubmission(provider: provider, reviewSubmissionID: reviewSubmissionID)
            print("    ✅ Submitted to App Store Review")
        }
    }

    static func submitReviewSubmission(
        provider: APIProvider,
        reviewSubmissionID: String
    ) async throws {
        let updateRequest = ReviewSubmissionUpdateRequest(
            data: .init(
                type: .reviewSubmissions,
                id: reviewSubmissionID,
                attributes: .init(isSubmitted: true)
            )
        )

        let request = APIEndpoint.v1.reviewSubmissions.id(reviewSubmissionID).patch(updateRequest)
        _ = try await provider.request(request)
    }

    static func findExistingReviewSubmission(
        provider: APIProvider,
        appID: String,
        platform: Platform
    ) async throws -> String? {
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

        var parameters = APIEndpoint.V1.ReviewSubmissions.GetParameters(filterApp: [appID])
        parameters.filterPlatform = [filterPlatform]
        parameters.filterState = [.readyForReview, .waitingForReview, .inReview]
        parameters.limit = 1

        let request = APIEndpoint.v1.reviewSubmissions.get(parameters: parameters)
        let response = try await provider.request(request)

        return response.data.first?.id
    }
}
