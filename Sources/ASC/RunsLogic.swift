import AppStoreConnect_Swift_SDK
import ArgumentParser
import Foundation

// MARK: - Output models

/// A single Xcode Cloud build run (`ciBuildRuns`), mirroring `gh run`.
struct RunSummary: Codable {
    let id: String
    let number: Int?
    let workflowName: String?
    let branch: String?
    let commitSha: String?
    let executionProgress: String?
    let completionStatus: String?
    let startReason: String?
    let createdDate: Date?
}

/// Issue counts for a build action (`ciIssueCounts`).
struct IssueCountsInfo: Codable {
    let errors: Int?
    let warnings: Int?
    let analyzerWarnings: Int?
    let testFailures: Int?
}

/// A single issue reported by a build action (`ciIssues`).
struct IssueInfo: Codable {
    let type: String?
    let message: String?
    let file: String?
    let line: Int?
    let category: String?
}

/// A downloadable artifact of a build action (`ciArtifacts`).
///
/// - Note: `downloadUrl` is a short-lived, pre-signed URL. It expires (typically
///   within minutes) and must be re-fetched from the API before use. Prefer
///   `asc runs download` over passing the URL around.
struct ArtifactInfo: Codable {
    let id: String
    let fileType: String?
    let fileName: String?
    let fileSize: Int?
    let downloadUrl: String?
}

/// A build action within a run (`ciBuildActions`) — the Build/Test/Analyze/Archive steps.
struct ActionInfo: Codable {
    let id: String
    let name: String?
    let actionType: String?
    let executionProgress: String?
    let completionStatus: String?
    let issueCounts: IssueCountsInfo?
    let issues: [IssueInfo]
    let artifacts: [ArtifactInfo]
}

/// A build run together with its actions — the payload of `asc runs view`.
struct RunDetail: Codable {
    let run: RunSummary
    let actions: [ActionInfo]
}

// MARK: - Logic

/// Fetch/parse logic for Xcode Cloud build runs, actions, issues and artifacts.
///
/// Kept separate from the command types so it can be exercised in isolation by
/// the test suite (mirroring `VersionLogic`).
enum RunsLogic {

    /// Resolves a workflow name to its `ciWorkflows` ID within a product.
    static func resolveWorkflowID(
        provider: APIProvider,
        productID: String,
        name: String
    ) async throws -> String {
        var parameters = APIEndpoint.V1.CiProducts.WithID.Workflows.GetParameters()
        parameters.fieldsCiWorkflows = [.name]

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

    /// Lists recent build runs for a product, optionally scoped to a single workflow.
    ///
    /// Results are sorted newest-first by build number.
    static func listRuns(
        provider: APIProvider,
        productID: String,
        workflowID: String?,
        limit: Int
    ) async throws -> [RunSummary] {
        let response: CiBuildRunsResponse
        if let workflowID {
            var parameters = APIEndpoint.V1.CiWorkflows.WithID.BuildRuns.GetParameters()
            parameters.fieldsCiBuildRuns = [
                .number, .executionProgress, .completionStatus,
                .createdDate, .startReason, .sourceCommit,
                .sourceBranchOrTag, .workflow
            ]
            parameters.sort = [.minusnumber]
            parameters.limit = limit
            parameters.include = [.sourceBranchOrTag, .workflow]
            parameters.fieldsScmGitReferences = [.name]
            parameters.fieldsCiWorkflows = [.name]

            let request = APIEndpoint.v1.ciWorkflows.id(workflowID).buildRuns.get(parameters: parameters)
            response = try await provider.request(request)
        } else {
            var parameters = APIEndpoint.V1.CiProducts.WithID.BuildRuns.GetParameters()
            parameters.fieldsCiBuildRuns = [
                .number, .executionProgress, .completionStatus,
                .createdDate, .startReason, .sourceCommit,
                .sourceBranchOrTag, .workflow
            ]
            parameters.sort = [.minusnumber]
            parameters.limit = limit
            parameters.include = [.sourceBranchOrTag, .workflow]
            parameters.fieldsScmGitReferences = [.name]
            parameters.fieldsCiWorkflows = [.name]

            let request = APIEndpoint.v1.ciProducts.id(productID).buildRuns.get(parameters: parameters)
            response = try await provider.request(request)
        }

        return summaries(from: response)
    }

    /// Resolves a human-facing build number to its full run summary.
    static func resolveRun(
        provider: APIProvider,
        productID: String,
        workflowID: String?,
        number: Int
    ) async throws -> RunSummary {
        // Build numbers are unique per workflow but the API offers no number
        // filter, so page through the most recent runs and match locally.
        let runs = try await listRuns(
            provider: provider,
            productID: productID,
            workflowID: workflowID,
            limit: 100
        )

        guard let matched = runs.first(where: { $0.number == number }) else {
            throw ValidationError(
                "Build #\(number) not found among the 100 most recent runs. "
                    + "Use 'asc runs list' to see available build numbers."
            )
        }
        return matched
    }

    /// Selects which actions to fetch and how much detail to include.
    struct ActionQuery {
        /// Only include actions whose name matches (case-insensitive).
        var actionFilter: String?
        /// Only include actions that failed.
        var onlyFailed = false
        /// Also fetch each action's issues.
        var includeIssues = false
        /// Also fetch each action's artifacts.
        var includeArtifacts = false
    }

    /// Fetches the actions of a run, optionally with their issues and artifacts.
    static func fetchActions(
        provider: APIProvider,
        runID: String,
        query: ActionQuery
    ) async throws -> [ActionInfo] {
        var parameters = APIEndpoint.V1.CiBuildRuns.WithID.Actions.GetParameters()
        parameters.fieldsCiBuildActions = [
            .name, .actionType, .executionProgress, .completionStatus, .issueCounts
        ]
        parameters.limit = 50

        let request = APIEndpoint.v1.ciBuildRuns.id(runID).actions.get(parameters: parameters)
        let response = try await provider.request(request)

        var actions = response.data
        if let actionFilter = query.actionFilter {
            actions = actions.filter { $0.attributes?.name?.caseInsensitiveCompare(actionFilter) == .orderedSame }
        }
        if query.onlyFailed {
            actions = actions.filter { $0.attributes?.completionStatus == .failed }
        }

        var result: [ActionInfo] = []
        for action in actions {
            let issues = query.includeIssues
                ? try await fetchIssues(provider: provider, actionID: action.id) : []
            let artifacts = query.includeArtifacts
                ? try await fetchArtifacts(provider: provider, actionID: action.id) : []

            let counts = action.attributes?.issueCounts.map {
                IssueCountsInfo(
                    errors: $0.errors,
                    warnings: $0.warnings,
                    analyzerWarnings: $0.analyzerWarnings,
                    testFailures: $0.testFailures
                )
            }

            result.append(ActionInfo(
                id: action.id,
                name: action.attributes?.name,
                actionType: action.attributes?.actionType?.rawValue,
                executionProgress: action.attributes?.executionProgress?.rawValue,
                completionStatus: action.attributes?.completionStatus?.rawValue,
                issueCounts: counts,
                issues: issues,
                artifacts: artifacts
            ))
        }
        return result
    }

    /// Fetches the issues (errors/warnings/test failures) of a single action.
    static func fetchIssues(
        provider: APIProvider,
        actionID: String
    ) async throws -> [IssueInfo] {
        let request = APIEndpoint.v1.ciBuildActions.id(actionID).issues.get(
            fieldsCiIssues: [.issueType, .message, .fileSource, .category],
            limit: 200
        )
        let response = try await provider.request(request)

        return response.data.map { issue in
            IssueInfo(
                type: issue.attributes?.issueType?.rawValue,
                message: issue.attributes?.message,
                file: issue.attributes?.fileSource?.path,
                line: issue.attributes?.fileSource?.lineNumber,
                category: issue.attributes?.category
            )
        }
    }

    /// Fetches the artifacts (logs, result bundles, archives …) of a single action.
    static func fetchArtifacts(
        provider: APIProvider,
        actionID: String
    ) async throws -> [ArtifactInfo] {
        let request = APIEndpoint.v1.ciBuildActions.id(actionID).artifacts.get(
            fieldsCiArtifacts: [.fileType, .fileName, .fileSize, .downloadURL],
            limit: 200
        )
        let response = try await provider.request(request)

        return response.data.map { artifact in
            ArtifactInfo(
                id: artifact.id,
                fileType: artifact.attributes?.fileType?.rawValue,
                fileName: artifact.attributes?.fileName,
                fileSize: artifact.attributes?.fileSize,
                downloadUrl: artifact.attributes?.downloadURL?.absoluteString
            )
        }
    }

    /// Downloads a pre-signed artifact URL to a local file, returning its path.
    ///
    /// The URL requires no App Store Connect credentials but is short-lived, so
    /// it should be fetched immediately before calling this.
    static func downloadArtifact(
        from urlString: String,
        fileName: String,
        to directory: URL
    ) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw ValidationError("Artifact has no valid download URL.")
        }

        let (tempURL, response) = try await URLSession.shared.download(from: url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ValidationError(
                "Failed to download \(fileName): HTTP \(http.statusCode). "
                    + "The pre-signed URL may have expired — re-run the command."
            )
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    // MARK: - Private

    /// Maps a `CiBuildRunsResponse` to `RunSummary`, resolving branch and
    /// workflow names from the response's `included` payload.
    private static func summaries(from response: CiBuildRunsResponse) -> [RunSummary] {
        var branchNameByID: [String: String] = [:]
        var workflowNameByID: [String: String] = [:]

        for item in response.included ?? [] {
            switch item {
            case .scmGitReference(let ref):
                if let name = ref.attributes?.name { branchNameByID[ref.id] = name }
            case .ciWorkflow(let workflow):
                if let name = workflow.attributes?.name { workflowNameByID[workflow.id] = name }
            default:
                break
            }
        }

        return response.data.map { run in
            let branchID = run.relationships?.sourceBranchOrTag?.data?.id
            let workflowID = run.relationships?.workflow?.data?.id
            let fullSha = run.attributes?.sourceCommit?.commitSha

            return RunSummary(
                id: run.id,
                number: run.attributes?.number,
                workflowName: workflowID.flatMap { workflowNameByID[$0] },
                branch: branchID.flatMap { branchNameByID[$0] },
                commitSha: fullSha.map { String($0.prefix(7)) },
                executionProgress: run.attributes?.executionProgress?.rawValue,
                completionStatus: run.attributes?.completionStatus?.rawValue,
                startReason: run.attributes?.startReason?.rawValue,
                createdDate: run.attributes?.createdDate
            )
        }
    }
}

// MARK: - Artifact file-type parsing

extension CiArtifact.Attributes.FileType {
    /// Parses a user-supplied `--type` value (case-insensitive) into a file type.
    static func parse(_ raw: String) throws -> CiArtifact.Attributes.FileType {
        guard let match = allCases.first(where: { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }) else {
            let available = allCases.map(\.rawValue).joined(separator: ", ")
            throw ValidationError("Unknown artifact type '\(raw)'. Available types: \(available)")
        }
        return match
    }
}
