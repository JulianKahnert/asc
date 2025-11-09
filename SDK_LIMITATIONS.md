# SDK Limitations and Required Fork Changes

## Overview
The `show` command currently displays "Build: Not selected" because the [appstoreconnect-swift-sdk](https://github.com/AvdLee/appstoreconnect-swift-sdk) doesn't fully implement the App Store Connect API's build-version relationship features.

## Root Cause
While the App Store Connect API supports querying build information efficiently, the Swift SDK has incomplete implementations:

1. **Missing Model Property**: `Build.Relationships` lacks the `appStoreVersion` property
2. **Missing Include Parameter**: `ListAppStoreVersionsOfApp` endpoint doesn't support the `include` parameter
3. **Missing Enum Case**: `BuildsResponse.Included` enum lacks `.appStoreVersion` case

## Required SDK Fork Changes

### 1. Add `appStoreVersion` to Build.Relationships

**File**: `Sources/Models/Build.swift`

**Location**: In `Build.Relationships` struct (around line 41-69)

**Change**:
```swift
public struct Relationships: Codable {
    // ... existing properties ...

    /// Build.Relationships.AppStoreVersion
    public let appStoreVersion: Build.Relationships.AppStoreVersion?

    // ... existing properties ...
}
```

**Add new relationship struct** (after existing relationship structs):
```swift
extension Build.Relationships {
    public struct AppStoreVersion: Codable {
        public let data: Build.Relationships.AppStoreVersion.Data?
        public let links: Build.Relationships.AppStoreVersion.Links?
    }
}

extension Build.Relationships.AppStoreVersion {
    public struct Data: Codable {
        public let id: String
        public let type: String = "appStoreVersions"
    }

    public struct Links: Codable {
        public let related: String?
        public let `self`: String?
    }
}
```

### 2. Add `include` parameter to ListAppStoreVersionsOfApp

**File**: `Sources/Endpoints/TestFlight/Apps/ListAppStoreVersionsForApp.swift`

**Location**: Endpoint function signature (line 16-21)

**Change**:
```swift
public static func appStoreVersions(
    ofAppWithId id: String,
    fields: [ListAppStoreVersionsOfApp.Field]? = nil,
    filters: [ListAppStoreVersionsOfApp.Filter]? = nil,
    include: [ListAppStoreVersionsOfApp.Include]? = nil,  // ADD THIS LINE
    limit: Int? = nil,
    next: PagedDocumentLinks? = nil
) -> APIEndpoint {
    var parameters = [String: Any]()
    if let fields = fields { parameters.add(fields) }
    if let filters = filters { parameters.add(filters) }
    if let include = include { parameters.add(include) }  // ADD THIS LINE
    // ... rest of function
}
```

**Add Include enum** (around line 70, after Filter enum):
```swift
extension ListAppStoreVersionsOfApp {
    /// Relationship data to include in the response.
    public enum Include: String, CaseIterable, NestableQueryParameter {
        case app
        case ageRatingDeclaration
        case appStoreVersionLocalizations
        case build
        case appStoreVersionPhasedRelease
        case gameCenterAppVersion
        case routingAppCoverage
        case appStoreReviewDetail
        case appStoreVersionSubmission
        case appClipDefaultExperience
        case appStoreVersionExperiments
        case appStoreVersionExperimentsV2
        case alternativeDistributionPackage

        static var key: String = "include"
        var pair: NestableQueryParameter.Pair { return (nil, rawValue) }
    }
}
```

### 3. Add `.appStoreVersion` case to BuildsResponse.Included

**File**: `Sources/Models/Responses/BuildsResponse.swift`

**Location**: In the `Included` enum

**Change**:
```swift
public enum Included: Codable {
    case app(App)
    case appEncryptionDeclaration(AppEncryptionDeclaration)
    case appStoreVersion(AppStoreVersion)  // ADD THIS LINE
    case betaAppReviewSubmission(BetaAppReviewSubmission)
    // ... other cases ...
}
```

**Update CodingKeys** (if present):
```swift
private enum CodingKeys: String, CodingKey {
    case app
    case appEncryptionDeclaration
    case appStoreVersion  // ADD THIS LINE
    case betaAppReviewSubmission
    // ... other keys ...
}
```

## Implementation After Fork

Once the SDK fork is available, update `ShowCommand.swift`:

```swift
private func getBuildsMap(
    provider: APIProvider,
    appID: String,
    platform: AppStoreVersionCreateRequest.Data.Attributes.Platform
) async throws -> [String: String] {
    let platformFilter: [ListBuilds.Filter.PreReleaseVersionPlatform] =
        platform == .iOS ? [.IOS] : [.MAC_OS]

    return try await withCheckedThrowingContinuation { continuation in
        let endpoint: APIEndpoint<BuildsResponse> = .builds(
            fields: [.builds([.version])],
            filter: [
                .app([appID]),
                .preReleaseVersionPlatform(platformFilter)
            ],
            include: [.appStoreVersion],
            sort: [.uploadedDateDescending]
        )

        provider.request(endpoint) { result in
            switch result {
            case .success(let response):
                var map: [String: String] = [:]

                for build in response.data {
                    guard let buildVersion = build.attributes?.version,
                          let versionID = build.relationships?.appStoreVersion?.data?.id else {
                        continue
                    }
                    map[versionID] = buildVersion
                }

                continuation.resume(returning: map)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}
```

## Alternative: Direct HTTP Implementation

If forking the SDK is not desired, implement direct HTTP requests:

```swift
// Create custom URLRequest with JWT auth
// Parse response manually
// Extract build->appStoreVersion relationships from included data
```

See commit history for URLSession-based implementation attempt.

## Verification

After implementing changes, verify with:
```bash
swift build
.build/arm64-apple-macosx/debug/asc show <bundle-id>
```

Expected output should show actual build numbers instead of "Not selected".

## API Documentation References

- [App Store Connect API - Builds](https://developer.apple.com/documentation/appstoreconnectapi/builds)
- [OpenAPI Specification](https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip)
  - `/v1/builds` supports `include=appStoreVersion`
  - `/v1/apps/{id}/appStoreVersions` supports `include=build`
  - `Build` schema includes `appStoreVersion` relationship
