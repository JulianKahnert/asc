//
//  ListAppsCommand.swift
//  ASC
//
//  Created by Julian Kahnert on 07.11.25.
//

import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

struct ListAppsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-apps",
        abstract: "List all apps in your App Store Connect account"
    )

    func run() async throws {
        print("🔑 Retrieving credentials from keychain...")

        // Use the centralized API provider creation
        let provider = try KeychainHelper.createAPIProvider()

        print("📱 Fetching apps from App Store Connect...\n")

        do {
            let apps = try await listApps(provider: provider)

            if apps.isEmpty {
                print("No apps found in your account.")
            } else {
                print("Found \(apps.count) app(s):\n")
                for app in apps {
                    print("📦 \(app.name)")
                    print("   App ID: \(app.id)")
                    print("   Bundle ID: \(app.bundleID)")
                    print("")
                }
            }
        } catch {
            print("❌ Error: \(error)")
            throw error
        }
    }

    private func listApps(provider: APIProvider) async throws -> [(id: String, name: String, bundleID: String)] {
        var parameters = APIEndpoint.V1.Apps.GetParameters()
        parameters.fieldsApps = [.name, .bundleID]
        parameters.limit = 200

        let request = APIEndpoint.v1.apps.get(parameters: parameters)
        let response = try await provider.request(request)

        let apps = response.data.map { app in
            (
                id: app.id,
                name: app.attributes?.name ?? "Unknown",
                bundleID: app.attributes?.bundleID ?? "Unknown"
            )
        }
        return apps
    }
}
