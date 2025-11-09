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
        let provider = try KeychainHelper.createAPIProvider()

        // Check if appID is a bundle ID (contains dots) and convert to App ID if needed
        var resolvedAppID = appID
        if appID.contains(".") {
            print("🔍 Resolving bundle ID '\(appID)' to App ID...")
            resolvedAppID = try await KeychainHelper.resolveAppID(provider: provider, bundleID: appID)
        }

        // Fetch iOS version info
        print("\n📱 iOS Versions:")
        try await showVersionInfo(provider: provider, appID: resolvedAppID, platform: .ios)

        // Fetch macOS version info
        print("\n💻 macOS Versions:")
        try await showVersionInfo(provider: provider, appID: resolvedAppID, platform: .macOs)
    }

    private func showVersionInfo(
        provider: APIProvider,
        appID: String,
        platform: Platform
    ) async throws {
        // Note: The SDK doesn't support the 'include' parameter for the list endpoint,
        // but the API does support it. We need to make individual requests for each version
        // to get build information. For now, we'll fetch builds separately.

        // First, get all versions using new SDK API
        var parameters = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters()
        parameters.fieldsAppStoreVersions = [.versionString, .platform, .appStoreState]
        parameters.limit = 10

        let request = APIEndpoint.v1.apps.id(appID).appStoreVersions.get(parameters: parameters)
        let response = try await provider.request(request)

        // Filter versions by platform
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
        platform: Platform
    ) async throws -> [String: String] {
        // Get all versions with build relationship included
        var parameters = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters()
        parameters.fieldsAppStoreVersions = [.versionString, .platform, .build]
        parameters.fieldsBuilds = [.version]
        parameters.include = [.build]
        parameters.limit = 50

        let request = APIEndpoint.v1.apps.id(appID).appStoreVersions.get(parameters: parameters)
        let response = try await provider.request(request)

        // Build map of versionID -> buildNumber
        var buildMap: [String: String] = [:]

        // Filter versions by platform
        let filteredVersions = response.data.filter {
            $0.attributes?.platform == platform
        }

        // Extract build information from included data
        for version in filteredVersions {
            // Check if this version has a build relationship
            if let buildData = version.relationships?.build?.data,
               let build = response.included?.compactMap({ includedItem -> Build? in
                   if case .build(let buildItem) = includedItem {
                       return buildItem
                   }
                   return nil
               }).first(where: { $0.id == buildData.id }),
               let buildVersion = build.attributes?.version {
                buildMap[version.id] = buildVersion
            }
        }

        return buildMap
    }
}
