/// JSON fixture strings that match real App Store Connect API responses for apps.
enum AppsFixtures {

    /// A successful response listing two apps.
    static let twoAppsResponse = """
    {
        "data": [
            {
                "type": "apps",
                "id": "123456789",
                "attributes": {
                    "name": "PDF Archiver",
                    "bundleId": "de.JulianKahnert.PDFArchiver"
                }
            },
            {
                "type": "apps",
                "id": "987654321",
                "attributes": {
                    "name": "My Other App",
                    "bundleId": "de.JulianKahnert.OtherApp"
                }
            }
        ],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/apps"
        },
        "meta": {
            "paging": {
                "total": 2,
                "limit": 200
            }
        }
    }
    """

    /// An empty apps response.
    static let emptyAppsResponse = """
    {
        "data": [],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/apps"
        },
        "meta": {
            "paging": {
                "total": 0,
                "limit": 200
            }
        }
    }
    """

    /// A single-app response used for bundle ID resolution.
    static let singleAppResponse = """
    {
        "data": [
            {
                "type": "apps",
                "id": "123456789",
                "attributes": {
                    "name": "PDF Archiver",
                    "bundleId": "de.JulianKahnert.PDFArchiver"
                }
            }
        ],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/apps"
        },
        "meta": {
            "paging": {
                "total": 1,
                "limit": 1
            }
        }
    }
    """
}
