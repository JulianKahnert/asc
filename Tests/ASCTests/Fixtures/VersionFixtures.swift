import AppStoreConnect_Swift_SDK
import Foundation

/// Factory helpers for constructing SDK model objects in tests.
/// Using the public memberwise initializers provided by the generated SDK types.
enum VersionFixtures {

    // MARK: - AppStoreVersion helpers

    static func makeVersion(
        id: String,
        versionString: String,
        platform: Platform,
        state: AppStoreVersionState
    ) -> AppStoreVersion {
        let attributes = AppStoreVersion.Attributes(
            platform: platform,
            versionString: versionString,
            appStoreState: state
        )
        return AppStoreVersion(
            type: .appStoreVersions,
            id: id,
            attributes: attributes
        )
    }

    // MARK: - Build helpers

    static func makeBuild(
        id: String,
        version: String,
        isExpired: Bool = false,
        processingState: Build.Attributes.ProcessingState = .valid
    ) -> Build {
        let attributes = Build.Attributes(
            version: version,
            isExpired: isExpired,
            processingState: processingState
        )
        return Build(
            type: .builds,
            id: id,
            attributes: attributes
        )
    }

    // MARK: - Canned fixture sets

    /// Two iOS versions for "1.2.0": one in PREPARE_FOR_SUBMISSION (the active
    /// one we want) and one old READY_FOR_SALE version from a previous release.
    static var iOSVersions: [AppStoreVersion] {
        [
            makeVersion(id: "ios-prepare-id", versionString: "1.2.0", platform: .ios, state: .prepareForSubmission),
            makeVersion(id: "ios-ready-id", versionString: "1.1.0", platform: .ios, state: .readyForSale)
        ]
    }

    /// A macOS READY_FOR_SALE version for a different version string — used to
    /// verify platform filtering keeps iOS and macOS results separate.
    static var macOSVersions: [AppStoreVersion] {
        [
            makeVersion(id: "macos-prepare-id", versionString: "1.2.0", platform: .macOs, state: .prepareForSubmission),
            makeVersion(id: "macos-ready-id", versionString: "1.1.0", platform: .macOs, state: .readyForSale)
        ]
    }

    /// Mix of iOS and macOS versions — both READY_FOR_SALE — for released-platforms tests.
    static var mixedReleasedVersions: [AppStoreVersion] {
        [
            makeVersion(id: "ios-rfs", versionString: "1.0.0", platform: .ios, state: .readyForSale),
            makeVersion(id: "macos-rfs", versionString: "1.0.0", platform: .macOs, state: .readyForSale)
        ]
    }

    /// Three builds for "1.2.0" / iOS. Sorted newest-first as the API would
    /// return them (the API sorts by -uploadedDate).
    static var iOS120Builds: [Build] {
        [
            makeBuild(id: "build-300", version: "300"),  // newest
            makeBuild(id: "build-200", version: "200"),
            makeBuild(id: "build-100", version: "100")
        ]
    }

    /// A build that is expired — should never be selected.
    static var expiredBuild: Build {
        makeBuild(id: "build-expired", version: "99", isExpired: true)
    }
}
