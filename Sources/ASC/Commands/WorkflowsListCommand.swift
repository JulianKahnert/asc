import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

/// Lists all Xcode Cloud workflows for a given app.
struct WorkflowsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all Xcode Cloud workflows for an app.",
        discussion: """
            Examples:
              $ asc workflows list com.example.app
              $ asc workflows com.example.app
            """
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect.")
    var appID: String

    func run() async throws {
        let provider = try KeychainHelper.createAPIProvider()
        let resolvedAppID = try await KeychainHelper.resolveAppID(provider: provider, appIDOrBundleID: appID)
        let productID = try await KeychainHelper.getCiProductID(provider: provider, appID: resolvedAppID)

        try await Self.execute(provider: provider, productID: productID, appIDDisplay: appID)
    }

    static func execute(
        provider: APIProvider,
        productID: String,
        appIDDisplay: String
    ) async throws {
        let workflows = try await listWorkflows(provider: provider, productID: productID)

        if workflows.isEmpty {
            print("No workflows found.")
            return
        }

        print("Workflows for \(appIDDisplay):\n")
        for workflow in workflows {
            let status = workflow.isEnabled ? "enabled" : "disabled"
            print("  \(workflow.name) (\(status)) — ID: \(workflow.id)")
        }
    }

    static func listWorkflows(
        provider: APIProvider,
        productID: String
    ) async throws -> [(id: String, name: String, isEnabled: Bool)] {
        var parameters = APIEndpoint.V1.CiProducts.WithID.Workflows.GetParameters()
        parameters.fieldsCiWorkflows = [.name, .isEnabled]

        let request = APIEndpoint.v1.ciProducts.id(productID).workflows.get(parameters: parameters)
        let response = try await provider.request(request)

        return response.data.map { workflow in
            (
                id: workflow.id,
                name: workflow.attributes?.name ?? "Unknown",
                isEnabled: workflow.attributes?.isEnabled ?? false
            )
        }
    }
}
