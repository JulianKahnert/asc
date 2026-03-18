import Testing
import AppStoreConnect_Swift_SDK
import Foundation

@testable import ASC

// MARK: - Tags

extension Tag {
    @Tag static var workflows: Self
}

// MARK: - WorkflowsListCommand tests

struct WorkflowsListCommandTests {

    @Test("listWorkflows parses two workflows correctly", .tags(.workflows))
    func listWorkflowsParsesResponse() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/workflows",
            method: "GET",
            json: WorkflowsFixtures.twoWorkflowsResponse
        )

        let workflows = try await WorkflowsListCommand.listWorkflows(
            provider: provider,
            productID: "ci-product-1"
        )

        #expect(workflows.count == 2)
        #expect(workflows[0].id == "wf-release")
        #expect(workflows[0].name == "Release Build")
        #expect(workflows[0].isEnabled == true)
        #expect(workflows[1].id == "wf-nightly")
        #expect(workflows[1].name == "Nightly Tests")
        #expect(workflows[1].isEnabled == false)
    }

    @Test("listWorkflows returns empty array when no workflows exist", .tags(.workflows))
    func listWorkflowsReturnsEmpty() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/workflows",
            method: "GET",
            json: WorkflowsFixtures.emptyWorkflowsResponse
        )

        let workflows = try await WorkflowsListCommand.listWorkflows(
            provider: provider,
            productID: "ci-product-1"
        )
        #expect(workflows.isEmpty)
    }
}

// MARK: - WorkflowsTriggerCommand tests

struct WorkflowsTriggerCommandTests {

    @Test("findWorkflow resolves the correct workflow ID by name", .tags(.workflows))
    func findWorkflowByName() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/workflows",
            method: "GET",
            json: WorkflowsFixtures.twoWorkflowsResponse
        )

        let workflowID = try await WorkflowsTriggerCommand.findWorkflow(
            provider: provider,
            productID: "ci-product-1",
            name: "Release Build"
        )
        #expect(workflowID == "wf-release")
    }

    @Test("findWorkflow throws when workflow name does not match", .tags(.workflows))
    func findWorkflowThrowsOnMismatch() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/workflows",
            method: "GET",
            json: WorkflowsFixtures.twoWorkflowsResponse
        )

        await #expect(throws: (any Error).self) {
            try await WorkflowsTriggerCommand.findWorkflow(
                provider: provider,
                productID: "ci-product-1",
                name: "Nonexistent Workflow"
            )
        }
    }

    @Test("findBranchReference resolves the correct branch ref ID", .tags(.workflows))
    func findBranchReference() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/repository",
            method: "GET",
            json: WorkflowsFixtures.repositoryResponse
        )
        executor.register(
            path: "/gitReferences",
            method: "GET",
            json: WorkflowsFixtures.gitReferencesResponse
        )

        let refID = try await WorkflowsTriggerCommand.findBranchReference(
            provider: provider,
            workflowID: "wf-release",
            branchName: "main"
        )
        #expect(refID == "ref-main")
    }

    @Test("triggerBuild returns the build run number and progress", .tags(.workflows))
    func triggerBuildReturnsRunInfo() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/v1/ciBuildRuns",
            method: "POST",
            json: WorkflowsFixtures.buildRunResponse
        )

        let result = try await WorkflowsTriggerCommand.triggerBuild(
            provider: provider,
            workflowID: "wf-release",
            branchReferenceID: "ref-main"
        )
        #expect(result.number == 42)
        #expect(result.executionProgress == .pending)
    }
}

// MARK: - WorkflowsStatusCommand tests

struct WorkflowsStatusCommandTests {

    @Test("listWorkflows parses workflows for status command", .tags(.workflows))
    func statusListWorkflows() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/workflows",
            method: "GET",
            json: WorkflowsFixtures.twoWorkflowsResponse
        )

        let workflows = try await WorkflowsStatusCommand.listWorkflows(
            provider: provider,
            productID: "ci-product-1"
        )
        #expect(workflows.count == 2)
        #expect(workflows[0].name == "Release Build")
    }

    @Test("getRecentBuildRuns parses build runs with included branch names", .tags(.workflows))
    func getRecentBuildRunsParsesBranches() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/buildRuns",
            method: "GET",
            json: WorkflowsFixtures.buildRunsStatusResponse
        )

        let runs = try await WorkflowsStatusCommand.getRecentBuildRuns(
            provider: provider,
            workflowID: "wf-release"
        )

        #expect(runs.count == 2)
        #expect(runs[0].number == 10)
        #expect(runs[0].sourceBranchName == "main")
        #expect(runs[0].completionStatus == .succeeded)
        #expect(runs[0].startReason == "MANUAL")
        #expect(runs[1].number == 9)
        #expect(runs[1].sourceBranchName == "develop")
        #expect(runs[1].completionStatus == .failed)
        #expect(runs[1].startReason == "GIT_REF_CHANGE")
    }

    @Test("formatStatus prefers completionStatus over executionProgress", .tags(.workflows))
    func formatStatusPrefersCompletion() {
        let status = WorkflowsStatusCommand.formatStatus(
            progress: .complete,
            completion: .succeeded
        )
        #expect(status == "SUCCEEDED")
    }

    @Test("formatStatus falls back to executionProgress when no completion", .tags(.workflows))
    func formatStatusFallsBackToProgress() {
        let status = WorkflowsStatusCommand.formatStatus(
            progress: .pending,
            completion: nil
        )
        #expect(status == "PENDING")
    }
}
