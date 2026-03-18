import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

/// Lists all apps in the App Store Connect account.
struct AppsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all apps in your App Store Connect account.",
        discussion: """
            Examples:
              $ asc apps list
            """
    )

    func run() async throws {
        let provider = try KeychainHelper.createAPIProvider()

        print("📱 Fetching apps from App Store Connect...\n")

        let apps = try await Self.listApps(provider: provider)

        if apps.isEmpty {
            print("No apps found in your account.")
        } else {
            print("Found \(apps.count) app(s):\n")
            for app in apps {
                print("  📦 \(app.name)")
                print("   App ID: \(app.id)")
                print("   Bundle ID: \(app.bundleID)")
                print("")
            }
        }
    }

    static func listApps(provider: APIProvider) async throws -> [(id: String, name: String, bundleID: String)] {
        var parameters = APIEndpoint.V1.Apps.GetParameters()
        parameters.fieldsApps = [.name, .bundleID]
        parameters.limit = 200

        let request = APIEndpoint.v1.apps.get(parameters: parameters)
        let response = try await provider.request(request)

        return response.data.map { app in
            (
                id: app.id,
                name: app.attributes?.name ?? "Unknown",
                bundleID: app.attributes?.bundleID ?? "Unknown"
            )
        }
    }
}
