import Testing
import AppStoreConnect_Swift_SDK
import Foundation

@testable import ASC

// MARK: - Tags

extension Tag {
    @Tag static var versions: Self
}

// MARK: - VersionSelectBuildCommand tests

struct VersionSelectBuildCommandTests {

    @Test("findVersion selects PREPARE_FOR_SUBMISSION version via mocked API", .tags(.versions))
    func findVersionSelectsPrepareForSubmission() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/v1/apps/123/appStoreVersions",
            method: "GET",
            json: VersionsAPIFixtures.iOSVersionsResponse
        )

        let versionID = try await VersionSelectBuildCommand.findVersion(
            provider: provider,
            appID: "123",
            versionString: "1.2.0",
            platform: .ios
        )
        #expect(versionID == "ios-prepare-id")
    }

    @Test("getNewestBuild returns the first build from a sorted API response", .tags(.versions))
    func getNewestBuildReturnsFirstBuild() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/v1/builds",
            method: "GET",
            json: BuildsFixtures.threeBuildsSortedResponse
        )

        let buildID = try await VersionSelectBuildCommand.getNewestBuild(
            provider: provider,
            appID: "123",
            versionString: "1.2.0",
            platform: .ios
        )
        #expect(buildID == "build-300", "Should select the newest build (build-300)")
    }

    @Test("getNewestBuild returns nil when no builds exist", .tags(.versions))
    func getNewestBuildReturnsNilWhenEmpty() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/v1/builds",
            method: "GET",
            json: BuildsFixtures.emptyBuildsResponse
        )

        let buildID = try await VersionSelectBuildCommand.getNewestBuild(
            provider: provider,
            appID: "123",
            versionString: "1.2.0",
            platform: .ios
        )
        #expect(buildID == nil)
    }
}

// MARK: - VersionCreateCommand tests

struct VersionCreateCommandTests {

    @Test("getReleasedPlatforms detects both iOS and macOS from API response", .tags(.versions))
    func getReleasedPlatformsDetectsBoth() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/v1/apps/123/appStoreVersions",
            method: "GET",
            json: VersionsAPIFixtures.bothPlatformsReleasedResponse
        )

        let platforms = try await VersionCreateCommand.getReleasedPlatforms(
            provider: provider,
            appID: "123"
        )
        #expect(platforms.count == 2)
        #expect(platforms.contains(.ios))
        #expect(platforms.contains(.macOs))
    }

    @Test("createVersion returns the new version ID from POST response", .tags(.versions))
    func createVersionReturnsNewID() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/v1/appStoreVersions",
            method: "POST",
            json: VersionsAPIFixtures.createdVersionResponse
        )

        let versionID = try await VersionCreateCommand.createVersion(
            provider: provider,
            appID: "123",
            versionString: "1.2.0",
            platform: .ios
        )
        #expect(versionID == "new-version-id")
    }

    @Test("findExistingVersion picks the right version from a duplicate-409 scenario", .tags(.versions))
    func findExistingVersionPicksPrepareForSubmission() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/v1/apps/123/appStoreVersions",
            method: "GET",
            json: VersionsAPIFixtures.iOSVersionsResponse
        )

        let versionID = try await VersionCreateCommand.findExistingVersion(
            provider: provider,
            appID: "123",
            versionString: "1.2.0",
            platform: .ios
        )
        #expect(versionID == "ios-prepare-id")
    }
}

// MARK: - VersionSubmitCommand tests

struct VersionSubmitCommandTests {

    @Test("findPreparedVersion returns the PREPARE_FOR_SUBMISSION version", .tags(.versions))
    func findPreparedVersionReturnsPFS() async throws {
        let (provider, executor) = try TestAPIProvider.make()

        executor.register(
            path: "/v1/apps/123/appStoreVersions",
            method: "GET",
            json: VersionsAPIFixtures.singlePrepareForSubmissionResponse
        )

        let result = try await VersionSubmitCommand.findPreparedVersion(
            provider: provider,
            appID: "123",
            platform: .ios
        )
        let (id, versionString) = try #require(result)
        #expect(id == "v-submit")
        #expect(versionString == "1.2.0")
    }

    @Test("findPreparedVersion returns nil when no version is prepared", .tags(.versions))
    func findPreparedVersionReturnsNilWhenNone() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/v1/apps/123/appStoreVersions",
            method: "GET",
            json: VersionsAPIFixtures.emptyVersionsResponse
        )

        let result = try await VersionSubmitCommand.findPreparedVersion(
            provider: provider,
            appID: "123",
            platform: .ios
        )
        #expect(result == nil)
    }
}
