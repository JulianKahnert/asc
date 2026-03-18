import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

/// Triggers an Xcode Cloud workflow run on a specific branch.
struct WorkflowsTriggerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trigger",
        abstract: "Trigger an Xcode Cloud workflow run.",
        discussion: """
            ⚠️  The workflow must have "Manual start" enabled in its start conditions, \
            otherwise triggering will fail.

            Examples:
              $ asc workflows trigger com.example.app --workflow "Release Build" --branch main
            """
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect.")
    var appID: String

    @Option(help: "Name of the workflow to trigger.")
    var workflow: String

    @Option(help: "Git branch name to build.")
    var branch: String

    func run() async throws {
        let provider = try KeychainHelper.createAPIProvider()
        let resolvedAppID = try await KeychainHelper.resolveAppID(provider: provider, appIDOrBundleID: appID)
        let productID = try await KeychainHelper.getCiProductID(provider: provider, appID: resolvedAppID)

        try await Self.execute(
            provider: provider,
            productID: productID,
            workflowName: workflow,
            branchName: branch
        )
    }

    static func execute(
        provider: APIProvider,
        productID: String,
        workflowName: String,
        branchName: String
    ) async throws {
        print("Finding workflow '\(workflowName)'...")
        let workflowID = try await findWorkflow(provider: provider, productID: productID, name: workflowName)

        print("Finding branch '\(branchName)'...")
        let branchReferenceID = try await findBranchReference(
            provider: provider,
            workflowID: workflowID,
            branchName: branchName
        )

        print("Triggering build...")
        let buildRun = try await triggerBuild(
            provider: provider,
            workflowID: workflowID,
            branchReferenceID: branchReferenceID
        )

        let number = buildRun.number.map { "#\($0)" } ?? "unknown"
        let status = buildRun.executionProgress?.rawValue ?? "UNKNOWN"
        print("Triggered workflow \"\(workflowName)\" on branch \"\(branchName)\"")
        print("Build run \(number), status: \(status)")
    }

    static func findWorkflow(
        provider: APIProvider,
        productID: String,
        name: String
    ) async throws -> String {
        var parameters = APIEndpoint.V1.CiProducts.WithID.Workflows.GetParameters()
        parameters.fieldsCiWorkflows = [.name, .isEnabled]

        let request = APIEndpoint.v1.ciProducts.id(productID).workflows.get(parameters: parameters)
        let response = try await provider.request(request)

        guard let matched = response.data.first(where: { $0.attributes?.name == name }) else {
            let available = response.data.compactMap { $0.attributes?.name }
            throw ValidationError(
                "Workflow '\(name)' not found. Available workflows: \(available.joined(separator: ", "))"
            )
        }

        return matched.id
    }

    static func findBranchReference(
        provider: APIProvider,
        workflowID: String,
        branchName: String
    ) async throws -> String {
        let repoRequest = APIEndpoint.v1.ciWorkflows.id(workflowID).repository.get()
        let repoResponse = try await provider.request(repoRequest)
        let repoID = repoResponse.data.id

        var parameters = APIEndpoint.V1.ScmRepositories.WithID.GitReferences.GetParameters()
        parameters.fieldsScmGitReferences = [.name, .kind]
        parameters.limit = 200

        let request = APIEndpoint.v1.scmRepositories.id(repoID).gitReferences.get(parameters: parameters)
        let response = try await provider.request(request)

        let branches = response.data.filter { $0.attributes?.kind == .branch }
        guard let matched = branches.first(where: { $0.attributes?.name == branchName }) else {
            let available = branches.compactMap { $0.attributes?.name }
            throw ValidationError(
                "Branch '\(branchName)' not found. Available branches: \(available.joined(separator: ", "))"
            )
        }

        return matched.id
    }

    static func triggerBuild(
        provider: APIProvider,
        workflowID: String,
        branchReferenceID: String
    ) async throws -> (number: Int?, executionProgress: CiExecutionProgress?) {
        let createRequest = CiBuildRunCreateRequest(
            data: .init(
                type: .ciBuildRuns,
                relationships: .init(
                    workflow: .init(
                        data: .init(type: .ciWorkflows, id: workflowID)
                    ),
                    sourceBranchOrTag: .init(
                        data: .init(type: .scmGitReferences, id: branchReferenceID)
                    )
                )
            )
        )

        let request = APIEndpoint.v1.ciBuildRuns.post(createRequest)
        let response = try await provider.request(request)

        return (
            number: response.data.attributes?.number,
            executionProgress: response.data.attributes?.executionProgress
        )
    }
}
