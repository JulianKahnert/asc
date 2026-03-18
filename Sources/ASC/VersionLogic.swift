import AppStoreConnect_Swift_SDK
import Foundation

/// Pure business-logic helpers that operate on already-fetched API data.
/// Kept free of `APIProvider` so they can be tested without network access.
public enum VersionLogic {

    /// The state priority order used when multiple versions match the same
    /// version string and platform.  The first match in this list wins.
    public static let priorityStates: [String] = [
        "PREPARE_FOR_SUBMISSION",
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "PENDING_DEVELOPER_RELEASE",
        "DEVELOPER_REJECTED",
        "REJECTED"
    ]

    /// Selects the best version ID from a list of versions that match the
    /// given `versionString` and `platform`.
    ///
    /// Priority is determined by `priorityStates`; falls back to the first
    /// match if none of the priority states are present.
    ///
    /// - Parameters:
    ///   - versions: The full list of `AppStoreVersion` items returned by the API.
    ///   - versionString: The desired version number (e.g. "2.1.0").
    ///   - platform: The desired platform.
    /// - Returns: The version ID of the best matching version, or `nil` if none
    ///   were found.
    public static func selectVersion(
        from versions: [AppStoreVersion],
        versionString: String,
        platform: Platform
    ) -> String? {
        let matching = versions.filter {
            $0.attributes?.versionString == versionString &&
            $0.attributes?.platform?.rawValue == platform.rawValue
        }

        for state in priorityStates {
            if let version = matching.first(where: {
                $0.attributes?.appStoreState?.rawValue == state
            }) {
                return version.id
            }
        }

        return matching.first?.id
    }

    /// Selects the best build from a pre-filtered list.
    ///
    /// The API is already asked to return only valid, non-expired builds
    /// sorted by upload date descending, so this simply returns the first
    /// element's ID.
    ///
    /// - Parameter builds: Builds already filtered by the API (valid,
    ///   non-expired, correct platform / version, sorted newest-first).
    /// - Returns: The ID of the newest build, or `nil` if the list is empty.
    public static func selectNewestBuild(from builds: [Build]) -> String? {
        builds.first?.id
    }

    /// Returns the platforms that have at least one version in the
    /// `READY_FOR_SALE` state from the provided version list.
    public static func releasedPlatforms(from versions: [AppStoreVersion]) -> [Platform] {
        var platforms = Set<Platform>()
        for version in versions {
            guard let state = version.attributes?.appStoreState,
                  let platform = version.attributes?.platform else { continue }
            if state == .readyForSale {
                platforms.insert(platform)
            }
        }
        return Array(platforms).sorted { $0.rawValue < $1.rawValue }
    }
}
