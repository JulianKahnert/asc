import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

/// Shows the status of recent build runs for Xcode Cloud workflows.
struct WorkflowsStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show status of recent Xcode Cloud build runs.",
        discussion: """
            Examples:
              $ asc workflows status com.example.app
              $ asc workflows status com.example.app --workflow "Release Build"
            """
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect.")
    var appID: String

    @Option(help: "Filter by workflow name.")
    var workflow: String?

    func run() async throws {
        let provider = try KeychainHelper.createAPIProvider()
        let resolvedAppID = try await KeychainHelper.resolveAppID(provider: provider, appIDOrBundleID: appID)
        let productID = try await KeychainHelper.getCiProductID(provider: provider, appID: resolvedAppID)

        try await Self.execute(provider: provider, productID: productID, workflowFilter: workflow)
    }

    static func execute(
        provider: APIProvider,
        productID: String,
        workflowFilter: String?
    ) async throws {
        let workflows = try await listWorkflows(provider: provider, productID: productID)

        let targetWorkflows: [(id: String, name: String)]
        if let workflowName = workflowFilter {
            guard let matched = workflows.first(where: { $0.name == workflowName }) else {
                let available = workflows.map(\.name)
                throw ValidationError(
                    "Workflow '\(workflowName)' not found. Available workflows: \(available.joined(separator: ", "))"
                )
            }
            targetWorkflows = [matched]
        } else {
            targetWorkflows = workflows
        }

        var foundAny = false

        for targetWorkflow in targetWorkflows {
            let buildRuns = try await getRecentBuildRuns(
                provider: provider,
                workflowID: targetWorkflow.id
            )

            guard !buildRuns.isEmpty else { continue }
            foundAny = true

            if workflowFilter != nil {
                print("Recent builds for \"\(targetWorkflow.name)\":\n")
            } else {
                print("\(targetWorkflow.name):")
            }

            for run in buildRuns {
                let number = run.number.map { "#\($0)" } ?? "?"
                let status = formatStatus(progress: run.executionProgress, completion: run.completionStatus)
                let branch = run.sourceBranchName ?? "unknown"
                let time = formatRelativeTime(run.createdDate)

                let reason = run.startReason.map { "(\($0))" } ?? ""
                let sha = run.sourceCommitSha ?? ""
                print("  \(number)  \(branch)  \(sha)  \(status)  \(time)  \(reason)")
            }
            print("")
        }

        if !foundAny {
            print("No recent builds found.")
        }
    }

    static func listWorkflows(
        provider: APIProvider,
        productID: String
    ) async throws -> [(id: String, name: String)] {
        var parameters = APIEndpoint.V1.CiProducts.WithID.Workflows.GetParameters()
        parameters.fieldsCiWorkflows = [.name]

        let request = APIEndpoint.v1.ciProducts.id(productID).workflows.get(parameters: parameters)
        let response = try await provider.request(request)

        return response.data.map { workflow in
            (id: workflow.id, name: workflow.attributes?.name ?? "Unknown")
        }
    }

    static func getRecentBuildRuns(
        provider: APIProvider,
        workflowID: String
    ) async throws -> [BuildRunInfo] {
        var parameters = APIEndpoint.V1.CiWorkflows.WithID.BuildRuns.GetParameters()
        parameters.fieldsCiBuildRuns = [
            .number, .executionProgress, .completionStatus,
            .createdDate, .sourceBranchOrTag, .startReason, .sourceCommit
        ]
        parameters.sort = [.minusnumber]
        parameters.limit = 5
        parameters.include = [.sourceBranchOrTag]
        parameters.fieldsScmGitReferences = [.name]

        let request = APIEndpoint.v1.ciWorkflows.id(workflowID).buildRuns.get(parameters: parameters)
        let response = try await provider.request(request)

        // Build a map of git reference IDs to branch names from included data
        var branchNameMap: [String: String] = [:]
        if let included = response.included {
            for item in included {
                if case .scmGitReference(let ref) = item {
                    if let name = ref.attributes?.name {
                        branchNameMap[ref.id] = name
                    }
                }
            }
        }

        return response.data.map { run in
            let branchRefID = run.relationships?.sourceBranchOrTag?.data?.id
            let branchName = branchRefID.flatMap { branchNameMap[$0] }

            let fullSha = run.attributes?.sourceCommit?.commitSha
            let shortSha = fullSha.map { String($0.prefix(7)) }

            return BuildRunInfo(
                number: run.attributes?.number,
                executionProgress: run.attributes?.executionProgress,
                completionStatus: run.attributes?.completionStatus,
                createdDate: run.attributes?.createdDate,
                sourceBranchName: branchName,
                startReason: run.attributes?.startReason?.rawValue,
                sourceCommitSha: shortSha
            )
        }
    }

    static func formatStatus(progress: CiExecutionProgress?, completion: CiCompletionStatus?) -> String {
        if let completion {
            return completion.rawValue
        }
        if let progress {
            return progress.rawValue
        }
        return "UNKNOWN"
    }

    static func formatRelativeTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = Int(-date.timeIntervalSinceNow)

        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}

struct BuildRunInfo {
    let number: Int?
    let executionProgress: CiExecutionProgress?
    let completionStatus: CiCompletionStatus?
    let createdDate: Date?
    let sourceBranchName: String?
    let startReason: String?
    let sourceCommitSha: String?
}
