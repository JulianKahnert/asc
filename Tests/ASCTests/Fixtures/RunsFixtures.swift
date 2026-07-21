/// JSON fixtures matching real App Store Connect CI responses for build runs,
/// actions, issues and artifacts.
enum RunsFixtures {

    /// Build runs for a product, including branch (scmGitReferences) and
    /// workflow (ciWorkflows) names in the `included` payload.
    static let productBuildRunsResponse = """
    {
        "data": [
            {
                "type": "ciBuildRuns",
                "id": "run-128",
                "attributes": {
                    "number": 128,
                    "executionProgress": "COMPLETE",
                    "completionStatus": "SUCCEEDED",
                    "createdDate": "2026-07-21T08:00:00+00:00",
                    "startReason": "MANUAL",
                    "sourceCommit": { "commitSha": "a1b2c3d4e5f6a7b8" }
                },
                "relationships": {
                    "sourceBranchOrTag": { "data": { "type": "scmGitReferences", "id": "ref-main" } },
                    "workflow": { "data": { "type": "ciWorkflows", "id": "wf-release" } }
                }
            },
            {
                "type": "ciBuildRuns",
                "id": "run-127",
                "attributes": {
                    "number": 127,
                    "executionProgress": "COMPLETE",
                    "completionStatus": "FAILED",
                    "createdDate": "2026-07-21T03:00:00+00:00",
                    "startReason": "GIT_REF_CHANGE",
                    "sourceCommit": { "commitSha": "9f8e7d6c5b4a3210" }
                },
                "relationships": {
                    "sourceBranchOrTag": { "data": { "type": "scmGitReferences", "id": "ref-main" } },
                    "workflow": { "data": { "type": "ciWorkflows", "id": "wf-release" } }
                }
            }
        ],
        "included": [
            { "type": "scmGitReferences", "id": "ref-main", "attributes": { "name": "main", "kind": "BRANCH" } },
            { "type": "ciWorkflows", "id": "wf-release", "attributes": { "name": "Release Build" } }
        ],
        "links": { "self": "https://api.appstoreconnect.apple.com/v1/ciProducts/ci-product-1/buildRuns" },
        "meta": { "paging": { "total": 2, "limit": 100 } }
    }
    """

    /// Actions of a build run: a succeeded Build and a failed Test.
    static let actionsResponse = """
    {
        "data": [
            {
                "type": "ciBuildActions",
                "id": "action-build",
                "attributes": {
                    "name": "Build",
                    "actionType": "BUILD",
                    "executionProgress": "COMPLETE",
                    "completionStatus": "SUCCEEDED",
                    "issueCounts": { "errors": 0, "warnings": 0, "analyzerWarnings": 0, "testFailures": 0 }
                }
            },
            {
                "type": "ciBuildActions",
                "id": "action-test",
                "attributes": {
                    "name": "Test",
                    "actionType": "TEST",
                    "executionProgress": "COMPLETE",
                    "completionStatus": "FAILED",
                    "issueCounts": { "errors": 2, "warnings": 1, "analyzerWarnings": 0, "testFailures": 2 }
                }
            }
        ],
        "links": { "self": "https://api.appstoreconnect.apple.com/v1/ciBuildRuns/run-127/actions" },
        "meta": { "paging": { "total": 2, "limit": 50 } }
    }
    """

    /// Issues of the failing Test action.
    static let issuesResponse = """
    {
        "data": [
            {
                "type": "ciIssues",
                "id": "issue-1",
                "attributes": {
                    "issueType": "ERROR",
                    "message": "XCTAssertEqual failed",
                    "category": "Test",
                    "fileSource": { "path": "MyTests.swift", "lineNumber": 42 }
                }
            },
            {
                "type": "ciIssues",
                "id": "issue-2",
                "attributes": {
                    "issueType": "ERROR",
                    "message": "unexpectedly found nil",
                    "category": "Test",
                    "fileSource": { "path": "MyTests.swift", "lineNumber": 88 }
                }
            }
        ],
        "links": { "self": "https://api.appstoreconnect.apple.com/v1/ciBuildActions/action-test/issues" },
        "meta": { "paging": { "total": 2, "limit": 200 } }
    }
    """

    /// Empty issues (for the succeeded Build action).
    static let emptyIssuesResponse = """
    {
        "data": [],
        "links": { "self": "https://api.appstoreconnect.apple.com/v1/ciBuildActions/action-build/issues" },
        "meta": { "paging": { "total": 0, "limit": 200 } }
    }
    """

    /// Artifacts of an action: a log bundle and a result bundle.
    static let artifactsResponse = """
    {
        "data": [
            {
                "type": "ciArtifacts",
                "id": "artifact-log",
                "attributes": {
                    "fileType": "LOG_BUNDLE",
                    "fileName": "Test.xcresult.log.zip",
                    "fileSize": 4404019,
                    "downloadUrl": "https://ci-artifacts.example.com/log.zip?X-Amz-Expires=900"
                }
            },
            {
                "type": "ciArtifacts",
                "id": "artifact-result",
                "attributes": {
                    "fileType": "RESULT_BUNDLE",
                    "fileName": "Test.xcresult.zip",
                    "fileSize": 18874368,
                    "downloadUrl": "https://ci-artifacts.example.com/result.zip?X-Amz-Expires=900"
                }
            }
        ],
        "links": { "self": "https://api.appstoreconnect.apple.com/v1/ciBuildActions/action-test/artifacts" },
        "meta": { "paging": { "total": 2, "limit": 200 } }
    }
    """

    /// Empty artifacts (for the succeeded Build action).
    static let emptyArtifactsResponse = """
    {
        "data": [],
        "links": { "self": "https://api.appstoreconnect.apple.com/v1/ciBuildActions/action-build/artifacts" },
        "meta": { "paging": { "total": 0, "limit": 200 } }
    }
    """
}
