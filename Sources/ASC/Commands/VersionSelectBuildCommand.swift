import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

/// Selects the newest build for a given version and assigns it for submission.
struct VersionSelectBuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "select-build",
        abstract: "Select newest build for submission.",
        discussion: """
            Examples:
              $ asc versions select-build com.example.app 1.2.0
              $ asc versions select-build com.example.app 1.2.0 --platform ios
            """
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect.")
    var appID: String

    @Argument(help: "The version string to select a build for (e.g., 1.0.0).")
    var version: String

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

        for platformValue in platforms {
            try await Self.executeForPlatform(
                provider: provider,
                appID: resolvedAppID,
                version: version,
                platform: platformValue
            )
        }
    }

    static func executeForPlatform(
        provider: APIProvider,
        appID: String,
        version: String,
        platform: Platform
    ) async throws {
        print("\n📱 Processing \(platform.name)...")

        print("🔍 Finding version \(version)...")
        guard let versionID = try await findVersion(provider: provider, appID: appID, versionString: version, platform: platform) else {
            print("⚠️  Version \(version) not found for platform \(platform.name)")
            return
        }

        print("🔍 Finding newest build for \(platform.name)...")
        guard let buildID = try await getNewestBuild(provider: provider, appID: appID, versionString: version, platform: platform) else {
            print("⚠️  No builds found for this app and platform \(platform.name)")
            return
        }

        print("🔗 Assigning build \(buildID) to version \(versionID)...")
        try await assignBuildToVersion(provider: provider, versionID: versionID, buildID: buildID)

        print("✅ Successfully assigned newest build to version \(version) for \(platform.name)")
    }

    static func findVersion(
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

        let matching = response.data.filter {
            $0.attributes?.versionString == versionString &&
            $0.attributes?.platform?.rawValue == platform.rawValue
        }

        // States where a build can be assigned to the version.
        let editableStates: [AppStoreVersionState] = [
            .prepareForSubmission,
            .developerRejected,
            .rejected,
        ]

        if let editable = matching.first(where: {
            guard let state = $0.attributes?.appStoreState else { return false }
            return editableStates.contains(state)
        }) {
            let state = editable.attributes?.appStoreState?.rawValue ?? "unknown"
            print("  Found version \(versionString) in state \(state)")
            return editable.id
        }

        // Report what state the version is actually in.
        if let found = matching.first, let state = found.attributes?.appStoreState {
            print("⚠️  Version \(versionString) for \(platform.name) is in state \(state.rawValue) — cannot assign builds")
        }
        return nil
    }

    static func getNewestBuild(
        provider: APIProvider,
        appID: String,
        versionString: String,
        platform: Platform
    ) async throws -> String? {
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
        parameters.filterPreReleaseVersionVersion = [versionString]
        parameters.filterBuildAudienceType = [.appStoreEligible]
        parameters.filterExpired = ["false"]
        parameters.filterProcessingState = [.valid]
        parameters.sort = [.minusuploadedDate]

        let request = APIEndpoint.v1.builds.get(parameters: parameters)
        let response = try await provider.request(request)

        if let build = response.data.first {
            let buildVersion = build.attributes?.version ?? "unknown"
            let processingState = build.attributes?.processingState?.rawValue ?? "unknown"
            let expired = build.attributes?.isExpired.map { String($0) } ?? "unknown"
            print("  Found build: id=\(build.id), version=\(buildVersion), processingState=\(processingState), expired=\(expired)")
            return build.id
        } else {
            return nil
        }
    }

    static func assignBuildToVersion(
        provider: APIProvider,
        versionID: String,
        buildID: String
    ) async throws {
        let linkageRequest = AppStoreVersionBuildLinkageRequest(
            data: .init(
                type: .builds,
                id: buildID
            )
        )

        let request = APIEndpoint.v1.appStoreVersions.id(versionID).relationships.build.patch(linkageRequest)
        try await provider.request(request)
    }
}
