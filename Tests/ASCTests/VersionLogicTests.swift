import Testing
import AppStoreConnect_Swift_SDK
import Foundation

@testable import ASC

// MARK: - Tags

extension Tag {
    @Tag static var versionSelection: Self
    @Tag static var buildSelection: Self
}

// MARK: - VersionLogic tests

struct VersionLogicTests {

    // MARK: Version selection

    @Test("Prefers PREPARE_FOR_SUBMISSION over READY_FOR_SALE for same version string",
          .tags(.versionSelection))
    func selectsActiveVersionOverReadyForSale() {
        let versions = VersionFixtures.iOSVersions
        let selected = VersionLogic.selectVersion(from: versions, versionString: "1.2.0", platform: .ios)
        #expect(selected == "ios-prepare-id", "Should pick the PREPARE_FOR_SUBMISSION version, not an older READY_FOR_SALE one")
    }

    @Test("Returns nil when no versions match the requested version string",
          .tags(.versionSelection))
    func returnsNilForUnknownVersionString() {
        let versions = VersionFixtures.iOSVersions
        let selected = VersionLogic.selectVersion(from: versions, versionString: "9.9.9", platform: .ios)
        #expect(selected == nil)
    }

    @Test("Filters by platform — iOS results do not include macOS versions",
          .tags(.versionSelection))
    func platformFilteringIsRespected() {
        let all = VersionFixtures.iOSVersions + VersionFixtures.macOSVersions
        let iosSelected  = VersionLogic.selectVersion(from: all, versionString: "1.2.0", platform: .ios)
        let macosSelected = VersionLogic.selectVersion(from: all, versionString: "1.2.0", platform: .macOs)
        #expect(iosSelected  == "ios-prepare-id")
        #expect(macosSelected == "macos-prepare-id")
    }

    @Test("Falls back to first match when no priority state is present",
          .tags(.versionSelection))
    func fallsBackToFirstMatchWhenNoPriorityState() {
        // Only a READY_FOR_SALE version exists for "1.1.0"
        let versions = VersionFixtures.iOSVersions
        let selected = VersionLogic.selectVersion(from: versions, versionString: "1.1.0", platform: .ios)
        #expect(selected == "ios-ready-id")
    }

    // MARK: Priority state ordering

    @Test("Priority state list starts with PREPARE_FOR_SUBMISSION",
          .tags(.versionSelection))
    func priorityStatesStartWithPrepareForSubmission() throws {
        let first = try #require(VersionLogic.priorityStates.first)
        #expect(first == "PREPARE_FOR_SUBMISSION")
    }

    // MARK: Build selection

    @Test("Picks the newest (first) build from a pre-sorted list",
          .tags(.buildSelection))
    func selectsNewestBuild() {
        let builds = VersionFixtures.iOS120Builds
        let buildID = VersionLogic.selectNewestBuild(from: builds)
        #expect(buildID == "build-300", "Expected the newest build (build-300) to be selected")
    }

    @Test("Returns nil when build list is empty",
          .tags(.buildSelection))
    func returnsNilForEmptyBuildList() {
        let buildID = VersionLogic.selectNewestBuild(from: [])
        #expect(buildID == nil)
    }

    // MARK: Released platforms

    @Test("Detects both iOS and macOS when both have READY_FOR_SALE versions")
    func detectsReleasedPlatforms() {
        let platforms = VersionLogic.releasedPlatforms(from: VersionFixtures.mixedReleasedVersions)
        #expect(platforms.count == 2)
        #expect(platforms.contains(.ios))
        #expect(platforms.contains(.macOs))
    }

    @Test("Returns empty array when no version is READY_FOR_SALE")
    func returnsEmptyWhenNothingReleased() {
        // A version list that contains only active (non-released) states.
        let activeOnly = [
            VersionFixtures.makeVersion(id: "v1", versionString: "1.0.0", platform: .ios, state: .prepareForSubmission),
            VersionFixtures.makeVersion(id: "v2", versionString: "1.0.0", platform: .macOs, state: .waitingForReview)
        ]
        let platforms = VersionLogic.releasedPlatforms(from: activeOnly)
        #expect(platforms.isEmpty, "PREPARE_FOR_SUBMISSION and WAITING_FOR_REVIEW must not be counted as released")
    }
}
