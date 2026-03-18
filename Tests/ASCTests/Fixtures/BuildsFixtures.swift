/// JSON fixture strings that match real App Store Connect API responses for builds.
enum BuildsFixtures {

    /// A builds response with three valid, non-expired builds sorted newest-first.
    static let threeBuildsSortedResponse = """
    {
        "data": [
            {
                "type": "builds",
                "id": "build-300",
                "attributes": {
                    "version": "300",
                    "expired": false,
                    "processingState": "VALID",
                    "uploadedDate": "2026-03-18T10:00:00+00:00"
                }
            },
            {
                "type": "builds",
                "id": "build-200",
                "attributes": {
                    "version": "200",
                    "expired": false,
                    "processingState": "VALID",
                    "uploadedDate": "2026-03-17T10:00:00+00:00"
                }
            },
            {
                "type": "builds",
                "id": "build-100",
                "attributes": {
                    "version": "100",
                    "expired": false,
                    "processingState": "VALID",
                    "uploadedDate": "2026-03-16T10:00:00+00:00"
                }
            }
        ],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/builds"
        },
        "meta": {
            "paging": {
                "total": 3,
                "limit": 50
            }
        }
    }
    """

    /// An empty builds response.
    static let emptyBuildsResponse = """
    {
        "data": [],
        "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/builds"
        },
        "meta": {
            "paging": {
                "total": 0,
                "limit": 50
            }
        }
    }
    """
}
