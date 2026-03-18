import Testing
import AppStoreConnect_Swift_SDK
import Foundation

@testable import ASC

// MARK: - Tags

extension Tag {
    @Tag static var apps: Self
}

// MARK: - AppsListCommand tests

struct AppsCommandTests {

    @Test("listApps parses a two-app response correctly", .tags(.apps))
    func listAppsParsesTwoApps() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/v1/apps",
            method: "GET",
            json: AppsFixtures.twoAppsResponse
        )

        let apps = try await AppsListCommand.listApps(provider: provider)

        #expect(apps.count == 2)
        #expect(apps[0].id == "123456789")
        #expect(apps[0].name == "PDF Archiver")
        #expect(apps[0].bundleID == "de.JulianKahnert.PDFArchiver")
        #expect(apps[1].id == "987654321")
        #expect(apps[1].name == "My Other App")
    }

    @Test("listApps returns empty array for empty response", .tags(.apps))
    func listAppsEmptyResponse() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/v1/apps",
            method: "GET",
            json: AppsFixtures.emptyAppsResponse
        )

        let apps = try await AppsListCommand.listApps(provider: provider)
        #expect(apps.isEmpty)
    }

    @Test("resolveAppID resolves bundle ID via API", .tags(.apps))
    func resolveAppIDWithBundleID() async throws {
        let (provider, executor) = try TestAPIProvider.make()
        executor.register(
            path: "/v1/apps",
            method: "GET",
            json: AppsFixtures.singleAppResponse
        )

        let appID = try await KeychainHelper.resolveAppID(
            provider: provider,
            appIDOrBundleID: "de.JulianKahnert.PDFArchiver"
        )
        #expect(appID == "123456789")
    }

    @Test("resolveAppID returns numeric ID unchanged", .tags(.apps))
    func resolveAppIDWithNumericID() async throws {
        let (provider, _) = try TestAPIProvider.make()

        // Numeric IDs (no dots) should be returned as-is without any API call.
        let appID = try await KeychainHelper.resolveAppID(
            provider: provider,
            appIDOrBundleID: "123456789"
        )
        #expect(appID == "123456789")
    }
}
