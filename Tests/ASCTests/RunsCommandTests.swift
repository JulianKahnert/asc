import Testing
import AppStoreConnect_Swift_SDK
import Foundation

@testable import ASC

// MARK: - Tags

extension Tag {
    @Tag static var runs: Self
}

// MARK: - RunsLogic: listing & resolving runs

struct RunsListLogicTests {

    @Test("listRuns parses build runs with branch and workflow names", .tags(.runs))
    func listRunsParsesResponse() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(path: "/buildRuns", method: "GET", json: RunsFixtures.productBuildRunsResponse)

        let runs = try await RunsLogic.listRuns(
            provider: provider,
            productID: "ci-product-1",
            workflowID: nil,
            limit: 100
        )

        #expect(runs.count == 2)
        #expect(runs[0].number == 128)
        #expect(runs[0].workflowName == "Release Build")
        #expect(runs[0].branch == "main")
        #expect(runs[0].commitSha == "a1b2c3d")
        #expect(runs[0].completionStatus == "SUCCEEDED")
        #expect(runs[1].number == 127)
        #expect(runs[1].completionStatus == "FAILED")
    }

    @Test("resolveRun finds a run by its build number", .tags(.runs))
    func resolveRunByNumber() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(path: "/buildRuns", method: "GET", json: RunsFixtures.productBuildRunsResponse)

        let run = try await RunsLogic.resolveRun(
            provider: provider,
            productID: "ci-product-1",
            workflowID: nil,
            number: 127
        )
        #expect(run.id == "run-127")
        #expect(run.completionStatus == "FAILED")
    }

    @Test("resolveRun throws when the build number is unknown", .tags(.runs))
    func resolveRunThrowsOnUnknownNumber() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(path: "/buildRuns", method: "GET", json: RunsFixtures.productBuildRunsResponse)

        await #expect(throws: (any Error).self) {
            try await RunsLogic.resolveRun(
                provider: provider,
                productID: "ci-product-1",
                workflowID: nil,
                number: 999
            )
        }
    }
}

// MARK: - RunsLogic: actions, issues, artifacts

struct RunsActionsLogicTests {

    /// Registers the actions endpoint plus per-action issues and artifacts.
    private func registerActionRoutes(_ executor: MockRequestExecutor) {
        executor.register(path: "/actions", method: "GET", json: RunsFixtures.actionsResponse)
        executor.register(path: "action-test/issues", method: "GET", json: RunsFixtures.issuesResponse)
        executor.register(path: "action-build/issues", method: "GET", json: RunsFixtures.emptyIssuesResponse)
        executor.register(path: "action-test/artifacts", method: "GET", json: RunsFixtures.artifactsResponse)
        executor.register(path: "action-build/artifacts", method: "GET", json: RunsFixtures.emptyArtifactsResponse)
    }

    @Test("fetchActions parses actions with their issues and artifacts", .tags(.runs))
    func fetchActionsParsesEverything() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        registerActionRoutes(executor)

        let actions = try await RunsLogic.fetchActions(
            provider: provider,
            runID: "run-127",
            query: .init(includeIssues: true, includeArtifacts: true)
        )

        #expect(actions.count == 2)

        let build = try #require(actions.first { $0.name == "Build" })
        #expect(build.completionStatus == "SUCCEEDED")
        #expect(build.issues.isEmpty)
        #expect(build.artifacts.isEmpty)

        let test = try #require(actions.first { $0.name == "Test" })
        #expect(test.completionStatus == "FAILED")
        #expect(test.issueCounts?.errors == 2)
        #expect(test.issues.count == 2)
        #expect(test.issues[0].file == "MyTests.swift")
        #expect(test.issues[0].line == 42)
        #expect(test.artifacts.count == 2)
        #expect(test.artifacts.contains { $0.fileType == "LOG_BUNDLE" })
        #expect(test.artifacts.contains { $0.fileType == "RESULT_BUNDLE" })
    }

    @Test("fetchActions with onlyFailed keeps just the failed action", .tags(.runs))
    func fetchActionsOnlyFailed() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        registerActionRoutes(executor)

        let actions = try await RunsLogic.fetchActions(
            provider: provider,
            runID: "run-127",
            query: .init(onlyFailed: true, includeIssues: true, includeArtifacts: true)
        )

        #expect(actions.count == 1)
        #expect(actions[0].name == "Test")
    }

    @Test("fetchActions honours the case-insensitive action filter", .tags(.runs))
    func fetchActionsActionFilter() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        registerActionRoutes(executor)

        let actions = try await RunsLogic.fetchActions(
            provider: provider,
            runID: "run-127",
            query: .init(actionFilter: "build")
        )

        #expect(actions.count == 1)
        #expect(actions[0].name == "Build")
    }
}

// MARK: - Artifact file-type parsing

struct ArtifactFileTypeTests {

    @Test("FileType.parse is case-insensitive", .tags(.runs))
    func parseCaseInsensitive() throws {
        #expect(try CiArtifact.Attributes.FileType.parse("log_bundle") == .logBundle)
        #expect(try CiArtifact.Attributes.FileType.parse("RESULT_BUNDLE") == .resultBundle)
    }

    @Test("FileType.parse throws on an unknown type", .tags(.runs))
    func parseThrowsOnUnknown() throws {
        #expect(throws: (any Error).self) {
            try CiArtifact.Attributes.FileType.parse("NONSENSE")
        }
    }
}
