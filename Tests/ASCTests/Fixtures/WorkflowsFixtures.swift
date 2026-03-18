/// JSON fixture strings that match real App Store Connect API responses for Xcode Cloud workflows.
enum WorkflowsFixtures {

    /// CI product response.
    static let ciProductResponse = """
    {
        "data": {
            "type": "ciProducts",
            "id": "ci-product-1",
            "attributes": {
                "name": "PDF Archiver",
                "productType": "APP"
            }
        },
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/apps/123/ciProduct"
        }
    }
    """

    /// A workflows response with two workflows.
    static let twoWorkflowsResponse = """
    {
        "data": [
            {
                "type": "ciWorkflows",
                "id": "wf-release",
                "attributes": {
                    "name": "Release Build",
                    "isEnabled": true
                }
            },
            {
                "type": "ciWorkflows",
                "id": "wf-nightly",
                "attributes": {
                    "name": "Nightly Tests",
                    "isEnabled": false
                }
            }
        ],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/ciProducts/ci-product-1/workflows"
        },
        "meta": {
            "paging": {
                "total": 2,
                "limit": 200
            }
        }
    }
    """

    /// An empty workflows response.
    static let emptyWorkflowsResponse = """
    {
        "data": [],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/ciProducts/ci-product-1/workflows"
        },
        "meta": {
            "paging": {
                "total": 0,
                "limit": 200
            }
        }
    }
    """

    /// Repository response for a workflow.
    static let repositoryResponse = """
    {
        "data": {
            "type": "scmRepositories",
            "id": "repo-1",
            "attributes": {
                "httpCloneUrl": "https://github.com/example/repo.git",
                "sshCloneUrl": "git@github.com:example/repo.git"
            }
        },
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/ciWorkflows/wf-release/repository"
        }
    }
    """

    /// Git references response with branches.
    static let gitReferencesResponse = """
    {
        "data": [
            {
                "type": "scmGitReferences",
                "id": "ref-main",
                "attributes": {
                    "name": "main",
                    "kind": "BRANCH"
                }
            },
            {
                "type": "scmGitReferences",
                "id": "ref-develop",
                "attributes": {
                    "name": "develop",
                    "kind": "BRANCH"
                }
            },
            {
                "type": "scmGitReferences",
                "id": "ref-tag",
                "attributes": {
                    "name": "v1.0.0",
                    "kind": "TAG"
                }
            }
        ],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/scmRepositories/repo-1/gitReferences"
        },
        "meta": {
            "paging": {
                "total": 3,
                "limit": 200
            }
        }
    }
    """

    /// A build run response (POST to /v1/ciBuildRuns).
    static let buildRunResponse = """
    {
        "data": {
            "type": "ciBuildRuns",
            "id": "run-42",
            "attributes": {
                "number": 42,
                "executionProgress": "PENDING"
            }
        },
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/ciBuildRuns/run-42"
        }
    }
    """

    /// Build runs response for status command (includes sourceBranchOrTag relationship and included scmGitReferences).
    static let buildRunsStatusResponse = """
    {
        "data": [
            {
                "type": "ciBuildRuns",
                "id": "run-10",
                "attributes": {
                    "number": 10,
                    "executionProgress": "COMPLETE",
                    "completionStatus": "SUCCEEDED",
                    "createdDate": "2026-03-18T08:00:00+00:00",
                    "startReason": "MANUAL"
                },
                "relationships": {
                    "sourceBranchOrTag": {
                        "data": {
                            "type": "scmGitReferences",
                            "id": "ref-main"
                        }
                    }
                }
            },
            {
                "type": "ciBuildRuns",
                "id": "run-9",
                "attributes": {
                    "number": 9,
                    "executionProgress": "COMPLETE",
                    "completionStatus": "FAILED",
                    "createdDate": "2026-03-17T12:00:00+00:00",
                    "startReason": "GIT_REF_CHANGE"
                },
                "relationships": {
                    "sourceBranchOrTag": {
                        "data": {
                            "type": "scmGitReferences",
                            "id": "ref-develop"
                        }
                    }
                }
            }
        ],
        "included": [
            {
                "type": "scmGitReferences",
                "id": "ref-main",
                "attributes": {
                    "name": "main",
                    "kind": "BRANCH"
                }
            },
            {
                "type": "scmGitReferences",
                "id": "ref-develop",
                "attributes": {
                    "name": "develop",
                    "kind": "BRANCH"
                }
            }
        ],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/ciWorkflows/wf-release/buildRuns"
        },
        "meta": {
            "paging": {
                "total": 2,
                "limit": 5
            }
        }
    }
    """

    /// Review submissions response (empty -- no existing submission).
    static let emptyReviewSubmissionsResponse = """
    {
        "data": [],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/reviewSubmissions"
        },
        "meta": {
            "paging": {
                "total": 0,
                "limit": 1
            }
        }
    }
    """

    /// Review submission create response.
    static let reviewSubmissionCreateResponse = """
    {
        "data": {
            "type": "reviewSubmissions",
            "id": "submission-1",
            "attributes": {
                "platform": "IOS",
                "state": "READY_FOR_REVIEW"
            }
        },
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/reviewSubmissions/submission-1"
        }
    }
    """

    /// Review submission item create response.
    static let reviewSubmissionItemCreateResponse = """
    {
        "data": {
            "type": "reviewSubmissionItems",
            "id": "item-1",
            "attributes": {
                "state": "READY_FOR_REVIEW"
            }
        },
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/reviewSubmissionItems/item-1"
        }
    }
    """

    /// Review submission update response (submitted).
    static let reviewSubmissionUpdateResponse = """
    {
        "data": {
            "type": "reviewSubmissions",
            "id": "submission-1",
            "attributes": {
                "platform": "IOS",
                "state": "WAITING_FOR_REVIEW"
            }
        },
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/reviewSubmissions/submission-1"
        }
    }
    """
}
