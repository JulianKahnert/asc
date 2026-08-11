import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

/// Lists recent Xcode Cloud build runs for an app (`gh run list`).
struct RunsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List recent Xcode Cloud build runs for an app.",
        discussion: """
            Examples:
              $ asc runs list com.example.app
              $ asc runs list com.example.app --workflow "Release Build" --limit 20
              $ asc runs list com.example.app --json
            """
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect.")
    var appID: String

    @Option(help: "Only show runs of this workflow.")
    var workflow: String?

    @Option(help: "Maximum number of runs to show.")
    var limit: Int = 10

    @Flag(name: .long, help: "Output the result as JSON.")
    var json = false

    func run() async throws {
        let provider = try KeychainHelper.createAPIProvider()
        let resolvedAppID = try await KeychainHelper.resolveAppID(provider: provider, appIDOrBundleID: appID)
        let productID = try await KeychainHelper.getCiProductID(provider: provider, appID: resolvedAppID)

        var workflowID: String?
        if let workflow {
            workflowID = try await RunsLogic.resolveWorkflowID(provider: provider, productID: productID, name: workflow)
        }

        let runs = try await RunsLogic.listRuns(
            provider: provider,
            productID: productID,
            workflowID: workflowID,
            limit: limit
        )

        if json {
            try JSONOutput.emit(runs)
            return
        }

        Self.printRuns(runs, showWorkflow: workflow == nil)
    }

    static func printRuns(_ runs: [RunSummary], showWorkflow: Bool) {
        guard !runs.isEmpty else {
            print("No build runs found.")
            return
        }

        for run in runs {
            let number = run.number.map { "#\($0)" } ?? "#?"
            let status = run.completionStatus ?? run.executionProgress ?? "UNKNOWN"
            let branch = run.branch ?? "unknown"
            let sha = run.commitSha ?? ""
            let time = WorkflowsStatusCommand.formatRelativeTime(run.createdDate)
            let workflowName = showWorkflow ? "  \(run.workflowName ?? "")" : ""
            print("  \(number)  \(status)\(workflowName)  \(branch)  \(sha)  \(time)")
        }
    }
}
