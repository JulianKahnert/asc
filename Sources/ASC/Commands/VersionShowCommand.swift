import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

/// Displays current prepared version and build info for an app.
struct VersionShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Display current prepared version and hints for an app.",
        discussion: """
            Examples:
              $ asc versions show com.example.app
              $ asc versions show 123456789
            """
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect.")
    var appID: String

    func run() async throws {
        let provider = try KeychainHelper.createAPIProvider()
        let resolvedAppID = try await KeychainHelper.resolveAppID(provider: provider, appIDOrBundleID: appID)

        try await Self.execute(provider: provider, appID: resolvedAppID)
    }

    static func execute(provider: APIProvider, appID: String) async throws {
        print("\n📱 iOS Versions:")
        try await showVersionInfo(provider: provider, appID: appID, platform: .ios)

        print("\n💻 macOS Versions:")
        try await showVersionInfo(provider: provider, appID: appID, platform: .macOs)
    }

    static func showVersionInfo(
        provider: APIProvider,
        appID: String,
        platform: Platform
    ) async throws {
        var parameters = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters()
        parameters.fieldsAppStoreVersions = [.versionString, .platform, .appStoreState]
        parameters.limit = 10

        let request = APIEndpoint.v1.apps.id(appID).appStoreVersions.get(parameters: parameters)
        let response = try await provider.request(request)

        let filteredVersions = response.data.filter {
            $0.attributes?.platform == platform
        }

        let versionData = filteredVersions.compactMap { version -> (String, String, String)? in
            guard let versionString = version.attributes?.versionString,
                  let state = version.attributes?.appStoreState?.rawValue else {
                return nil
            }
            return (version.id, versionString, state)
        }

        if versionData.isEmpty {
            print("  No versions found")
            return
        }

        let buildMap = try await getBuildsMap(provider: provider, appID: appID, platform: platform)

        for (versionID, versionString, state) in versionData {
            print("  Version: \(versionString)")
            print("  State: \(state)")

            if let buildNumber = buildMap[versionID] {
                print("  Build: \(buildNumber)")
            } else {
                print("  Build: Not selected")
            }
            print("")
        }
    }

    static func getBuildsMap(
        provider: APIProvider,
        appID: String,
        platform: Platform
    ) async throws -> [String: String] {
        var parameters = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters()
        parameters.fieldsAppStoreVersions = [.versionString, .platform, .build]
        parameters.fieldsBuilds = [.version]
        parameters.include = [.build]
        parameters.limit = 50

        let request = APIEndpoint.v1.apps.id(appID).appStoreVersions.get(parameters: parameters)
        let response = try await provider.request(request)

        // Pre-compute a lookup of build ID → build version from included data
        var buildVersionByID: [String: String] = [:]
        if let included = response.included {
            for item in included {
                if case .build(let build) = item, let version = build.attributes?.version {
                    buildVersionByID[build.id] = version
                }
            }
        }

        var buildMap: [String: String] = [:]
        let filteredVersions = response.data.filter {
            $0.attributes?.platform == platform
        }

        for version in filteredVersions {
            if let buildID = version.relationships?.build?.data?.id,
               let buildVersion = buildVersionByID[buildID] {
                buildMap[version.id] = buildVersion
            }
        }

        return buildMap
    }
}
