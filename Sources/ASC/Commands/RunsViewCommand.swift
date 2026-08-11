import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

/// Shows a single build run with its actions, issues and artifacts (`gh run view`).
struct RunsViewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "Show a build run's actions, issues and artifacts.",
        discussion: """
            Prints each action (Build/Test/Analyze/Archive) with its status and
            issue counts. Failing actions list their errors inline, and each
            action's downloadable artifacts are shown (use 'asc runs download').

            Examples:
              $ asc runs view com.example.app 42
              $ asc runs view com.example.app 42 --failed
              $ asc runs view com.example.app 42 --json
            """
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect.")
    var appID: String

    @Argument(help: "The build run number (as shown by 'asc runs list').")
    var number: Int

    @Option(help: "Disambiguate the build number to a specific workflow.")
    var workflow: String?

    @Flag(help: "Only show actions that failed.")
    var failed = false

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

        let run = try await RunsLogic.resolveRun(
            provider: provider,
            productID: productID,
            workflowID: workflowID,
            number: number
        )

        let actions = try await RunsLogic.fetchActions(
            provider: provider,
            runID: run.id,
            query: .init(onlyFailed: failed, includeIssues: true, includeArtifacts: true)
        )

        let detail = RunDetail(run: run, actions: actions)

        if json {
            try JSONOutput.emit(detail)
            return
        }

        Self.printDetail(detail)
    }

    static func printDetail(_ detail: RunDetail) {
        let run = detail.run
        let number = run.number.map { "#\($0)" } ?? "#?"
        let status = run.completionStatus ?? run.executionProgress ?? "UNKNOWN"
        let branch = run.branch ?? "unknown"
        let sha = run.commitSha ?? ""
        print("Run \(number)  \(status)  \(run.workflowName ?? "")  \(branch)@\(sha)\n")

        if detail.actions.isEmpty {
            print("  No actions found.")
            return
        }

        for action in detail.actions {
            let actionStatus = action.completionStatus ?? action.executionProgress ?? "UNKNOWN"
            let counts = Self.formatCounts(action.issueCounts)
            print("  \(action.name ?? action.actionType ?? "Action")  \(actionStatus)\(counts)")

            for issue in action.issues {
                let location = issue.file.map { file in
                    issue.line.map { "\(file):\($0)" } ?? file
                } ?? ""
                let type = issue.type ?? "ISSUE"
                let message = issue.message ?? ""
                print("       \(type)  \(location)  \(message)")
            }

            for artifact in action.artifacts {
                let type = artifact.fileType ?? "ARTIFACT"
                let name = artifact.fileName ?? artifact.id
                let size = Self.formatSize(artifact.fileSize)
                print("       ↓ \(type)  \(name)  \(size)")
            }
            print("")
        }
    }

    static func formatCounts(_ counts: IssueCountsInfo?) -> String {
        guard let counts else { return "" }
        var parts: [String] = []
        if let errors = counts.errors, errors > 0 { parts.append("\(errors) error\(errors == 1 ? "" : "s")") }
        if let failures = counts.testFailures, failures > 0 {
            parts.append("\(failures) test failure\(failures == 1 ? "" : "s")")
        }
        if let warnings = counts.warnings, warnings > 0 {
            parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "" : "  (\(parts.joined(separator: ", ")))"
    }

    static func formatSize(_ bytes: Int?) -> String {
        guard let bytes else { return "" }
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return unit == 0 ? "\(bytes) B" : String(format: "%.1f %@", value, units[unit])
    }
}
