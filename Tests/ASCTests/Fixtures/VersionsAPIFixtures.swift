/// JSON fixture strings that match real App Store Connect API responses for app store versions.
enum VersionsAPIFixtures {

    /// Versions response with both PREPARE_FOR_SUBMISSION and READY_FOR_SALE versions for iOS.
    static let iOSVersionsResponse = """
    {
        "data": [
            {
                "type": "appStoreVersions",
                "id": "ios-prepare-id",
                "attributes": {
                    "versionString": "1.2.0",
                    "platform": "IOS",
                    "appStoreState": "PREPARE_FOR_SUBMISSION"
                }
            },
            {
                "type": "appStoreVersions",
                "id": "ios-ready-id",
                "attributes": {
                    "versionString": "1.1.0",
                    "platform": "IOS",
                    "appStoreState": "READY_FOR_SALE"
                }
            }
        ],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/apps/123/appStoreVersions"
        },
        "meta": {
            "paging": {
                "total": 2,
                "limit": 50
            }
        }
    }
    """

    /// Versions response containing both iOS and macOS READY_FOR_SALE versions (for released platforms detection).
    static let bothPlatformsReleasedResponse = """
    {
        "data": [
            {
                "type": "appStoreVersions",
                "id": "ios-rfs",
                "attributes": {
                    "versionString": "1.1.0",
                    "platform": "IOS",
                    "appStoreState": "READY_FOR_SALE"
                }
            },
            {
                "type": "appStoreVersions",
                "id": "macos-rfs",
                "attributes": {
                    "versionString": "1.1.0",
                    "platform": "MAC_OS",
                    "appStoreState": "READY_FOR_SALE"
                }
            }
        ],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/apps/123/appStoreVersions"
        },
        "meta": {
            "paging": {
                "total": 2,
                "limit": 200
            }
        }
    }
    """

    /// A version-create response (POST to /v1/appStoreVersions).
    static let createdVersionResponse = """
    {
        "data": {
            "type": "appStoreVersions",
            "id": "new-version-id",
            "attributes": {
                "versionString": "1.2.0",
                "platform": "IOS",
                "appStoreState": "PREPARE_FOR_SUBMISSION"
            }
        },
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/appStoreVersions/new-version-id"
        }
    }
    """

    /// A localization list response with one existing localization.
    static let localizationsResponse = """
    {
        "data": [
            {
                "type": "appStoreVersionLocalizations",
                "id": "loc-de",
                "attributes": {
                    "locale": "de-DE",
                    "whatsNew": "Alte Notizen"
                }
            }
        ],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/appStoreVersions/v1/appStoreVersionLocalizations"
        },
        "meta": {
            "paging": {
                "total": 1,
                "limit": 50
            }
        }
    }
    """

    /// A localization update response (PATCH).
    static let localizationUpdateResponse = """
    {
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": "loc-de",
            "attributes": {
                "locale": "de-DE",
                "whatsNew": "Neue Notizen"
            }
        },
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/loc-de"
        }
    }
    """

    /// A localization create response (POST).
    static let localizationCreateResponse = """
    {
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": "loc-en",
            "attributes": {
                "locale": "en-US",
                "whatsNew": "Bug fixes"
            }
        },
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/loc-en"
        }
    }
    """

    /// A single PREPARE_FOR_SUBMISSION version response, used to test findPreparedVersion.
    static let singlePrepareForSubmissionResponse = """
    {
        "data": [
            {
                "type": "appStoreVersions",
                "id": "v-submit",
                "attributes": {
                    "versionString": "1.2.0",
                    "platform": "IOS",
                    "appStoreState": "PREPARE_FOR_SUBMISSION"
                }
            }
        ],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/apps/123/appStoreVersions"
        },
        "meta": {
            "paging": {
                "total": 1,
                "limit": 10
            }
        }
    }
    """

    /// An empty versions response, used to test nil/empty fallback paths.
    static let emptyVersionsResponse = """
    {
        "data": [],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/apps/123/appStoreVersions"
        },
        "meta": {
            "paging": {
                "total": 0,
                "limit": 10
            }
        }
    }
    """

    /// A version update response (PATCH to /v1/appStoreVersions/{id}).
    static let versionUpdateResponse = """
    {
        "data": {
            "type": "appStoreVersions",
            "id": "ios-prepare-id",
            "attributes": {
                "versionString": "1.2.0",
                "platform": "IOS",
                "appStoreState": "PREPARE_FOR_SUBMISSION"
            }
        },
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/appStoreVersions/ios-prepare-id"
        }
    }
    """
}
