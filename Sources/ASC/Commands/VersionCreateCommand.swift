import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

/// Creates or updates an app version with release notes for all released platforms.
struct VersionCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create or update an app version with release notes.",
        discussion: """
            Examples:
              $ asc versions create com.example.app 1.2.0 --hint '{"german": "Fehlerbehebungen", "english": "Bug fixes"}'
              $ asc versions create 123456789 2.0.0 --hintGerman "Neu" --hintEnglish "New"
            """
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect.")
    var appID: String

    @Argument(help: "The version string (e.g., 1.0.0).")
    var version: String

    @Option(name: .customLong("hintGerman"), help: "German release notes.")
    var hintGerman: String?

    @Option(name: .customLong("hintEnglish"), help: "English release notes.")
    var hintEnglish: String?

    @Option(name: .customLong("hint"), help: "JSON string with 'german' and 'english' keys containing release notes.")
    var hintJSON: String?

    func run() async throws {
        let (germanHint, englishHint) = try parseHints()

        let provider = try KeychainHelper.createAPIProvider()
        let resolvedAppID = try await KeychainHelper.resolveAppID(provider: provider, appIDOrBundleID: appID)

        try await Self.execute(
            provider: provider,
            appID: resolvedAppID,
            version: version,
            germanHint: germanHint,
            englishHint: englishHint
        )
    }

    static func execute(
        provider: APIProvider,
        appID: String,
        version: String,
        germanHint: String,
        englishHint: String
    ) async throws {
        print("📱 Creating/updating version \(version) for app \(appID)...")

        print("🔍 Checking which platforms have been released...")
        let releasedPlatforms = try await getReleasedPlatforms(
            provider: provider,
            appID: appID
        )

        if releasedPlatforms.isEmpty {
            throw ValidationError("No platforms have been released yet for this app. Please release the app on at least one platform first.")
        }

        print("✅ Found released platforms: \(releasedPlatforms.map { $0.rawValue }.joined(separator: ", "))")

        var versionIDs: [(platform: Platform, id: String)] = []

        for platform in releasedPlatforms {
            print("Creating/finding \(platform.name) version...")
            let versionID = try await createOrFindVersion(
                provider: provider,
                appID: appID,
                versionString: version,
                platform: platform
            )
            print("✅ \(platform.name) version ID: \(versionID)")
            versionIDs.append((platform: platform, id: versionID))
        }

        for (platform, versionID) in versionIDs {
            print("📝 Updating \(platform.name) release notes...")
            try await updateOrCreateLocalization(
                provider: provider,
                versionID: versionID,
                locale: "de-DE",
                whatsNew: germanHint
            )
            try await updateOrCreateLocalization(
                provider: provider,
                versionID: versionID,
                locale: "en-US",
                whatsNew: englishHint
            )
        }

        print("✅ Successfully updated versions with release notes")
    }

    private func parseHints() throws -> (german: String, english: String) {
        if let jsonString = hintJSON {
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw ValidationError("Invalid JSON string encoding")
            }

            guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw ValidationError("Invalid JSON format. Expected object with 'german' and 'english' keys")
            }

            guard let german = json["german"] as? String,
                  let english = json["english"] as? String else {
                throw ValidationError("JSON must contain 'german' and 'english' string keys")
            }

            return (german, english)
        }

        guard let german = hintGerman, let english = hintEnglish else {
            throw ValidationError("Either provide --hint with JSON, or both --hintGerman and --hintEnglish")
        }

        return (german, english)
    }

    static func getReleasedPlatforms(
        provider: APIProvider,
        appID: String
    ) async throws -> [Platform] {
        var parameters = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters()
        parameters.fieldsAppStoreVersions = [.platform, .appStoreState]
        parameters.limit = 200

        let request = APIEndpoint.v1.apps.id(appID).appStoreVersions.get(parameters: parameters)
        let response = try await provider.request(request)

        return VersionLogic.releasedPlatforms(from: response.data)
    }

    static func createOrFindVersion(
        provider: APIProvider,
        appID: String,
        versionString: String,
        platform: Platform
    ) async throws -> String {
        do {
            return try await createVersion(
                provider: provider,
                appID: appID,
                versionString: versionString,
                platform: platform
            )
        } catch {
            let errorString = String(describing: error)
            if errorString.contains("409") && errorString.contains("DUPLICATE") {
                print("   Version already exists, finding it...")
                return try await findExistingVersion(
                    provider: provider,
                    appID: appID,
                    versionString: versionString,
                    platform: platform
                )
            }

            if errorString.contains("409") && errorString.contains("You cannot create a new version of the App in the current state") {
                print("   ⚠️  Cannot create new version - an active version already exists")
                print("   🔍 Finding active version to update...")

                let activeVersion = try await findActiveVersion(
                    provider: provider,
                    appID: appID,
                    platform: platform
                )

                if let activeVersion {
                    print("   📝 Found active version \(activeVersion.versionString) (ID: \(activeVersion.id))")
                    print("   🔄 Updating version number from \(activeVersion.versionString) to \(versionString)...")

                    try await updateVersionNumber(
                        provider: provider,
                        versionID: activeVersion.id,
                        newVersionString: versionString
                    )

                    print("   ✅ Version number updated to \(versionString)")
                    return activeVersion.id
                } else {
                    throw ValidationError("Cannot find active version to update")
                }
            }

            throw error
        }
    }

    static func createVersion(
        provider: APIProvider,
        appID: String,
        versionString: String,
        platform: Platform
    ) async throws -> String {
        let attributes = AppStoreVersionCreateRequest.Data.Attributes(
            platform: platform,
            versionString: versionString
        )
        let appRelationship = AppStoreVersionCreateRequest.Data.Relationships.App(
            data: .init(type: .apps, id: appID)
        )
        let relationships = AppStoreVersionCreateRequest.Data.Relationships(
            app: appRelationship,
            appStoreVersionLocalizations: nil,
            build: nil
        )
        let data = AppStoreVersionCreateRequest.Data(
            type: .appStoreVersions,
            attributes: attributes,
            relationships: relationships
        )
        let request = AppStoreVersionCreateRequest(data: data)

        let apiRequest = APIEndpoint.v1.appStoreVersions.post(request)
        let response = try await provider.request(apiRequest)
        return response.data.id
    }

    static func findExistingVersion(
        provider: APIProvider,
        appID: String,
        versionString: String,
        platform: Platform
    ) async throws -> String {
        var parameters = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters()
        parameters.fieldsAppStoreVersions = [.versionString, .platform, .appStoreState]
        parameters.limit = 50

        let request = APIEndpoint.v1.apps.id(appID).appStoreVersions.get(parameters: parameters)
        let response = try await provider.request(request)

        guard let versionID = VersionLogic.selectVersion(from: response.data, versionString: versionString, platform: platform) else {
            throw ValidationError("Could not find existing version \(versionString) for platform \(platform.rawValue)")
        }

        return versionID
    }

    static func findActiveVersion(
        provider: APIProvider,
        appID: String,
        platform: Platform
    ) async throws -> (id: String, versionString: String)? {
        var parameters = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters()
        parameters.fieldsAppStoreVersions = [.versionString, .platform, .appStoreState]
        parameters.limit = 10

        let request = APIEndpoint.v1.apps.id(appID).appStoreVersions.get(parameters: parameters)
        let response = try await provider.request(request)

        let activeStates = ["PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"]
        let activeVersion = response.data
            .filter { $0.attributes?.platform == platform }
            .first { version in
                guard let state = version.attributes?.appStoreState?.rawValue else { return false }
                return activeStates.contains(state)
            }

        guard let version = activeVersion,
              let versionString = version.attributes?.versionString else {
            return nil
        }
        return (id: version.id, versionString: versionString)
    }

    static func updateVersionNumber(
        provider: APIProvider,
        versionID: String,
        newVersionString: String
    ) async throws {
        let attributes = AppStoreVersionUpdateRequest.Data.Attributes(versionString: newVersionString)
        let data = AppStoreVersionUpdateRequest.Data(
            type: .appStoreVersions,
            id: versionID,
            attributes: attributes
        )
        let updateRequest = AppStoreVersionUpdateRequest(data: data)

        let apiRequest = APIEndpoint.v1.appStoreVersions.id(versionID).patch(updateRequest)
        _ = try await provider.request(apiRequest)
    }

    static func updateOrCreateLocalization(
        provider: APIProvider,
        versionID: String,
        locale: String,
        whatsNew: String
    ) async throws {
        let existingLocalizations = try await listLocalizations(provider: provider, versionID: versionID)

        if let existingLocalization = existingLocalizations.first(where: { $0.locale == locale }) {
            try await updateLocalization(
                provider: provider,
                localizationID: existingLocalization.id,
                whatsNew: whatsNew
            )
            print("✅ Updated \(locale) localization")
        } else {
            try await createLocalization(
                provider: provider,
                versionID: versionID,
                locale: locale,
                whatsNew: whatsNew
            )
        }
    }

    static func listLocalizations(
        provider: APIProvider,
        versionID: String
    ) async throws -> [(id: String, locale: String)] {
        let request = APIEndpoint.v1.appStoreVersions.id(versionID).appStoreVersionLocalizations.get()
        let response = try await provider.request(request)

        return response.data.map { localization in
            (
                id: localization.id,
                locale: localization.attributes?.locale ?? ""
            )
        }
    }

    static func updateLocalization(
        provider: APIProvider,
        localizationID: String,
        whatsNew: String
    ) async throws {
        let attributes = AppStoreVersionLocalizationUpdateRequest.Data.Attributes(whatsNew: whatsNew)
        let data = AppStoreVersionLocalizationUpdateRequest.Data(
            type: .appStoreVersionLocalizations,
            id: localizationID,
            attributes: attributes
        )
        let updateRequest = AppStoreVersionLocalizationUpdateRequest(data: data)

        let apiRequest = APIEndpoint.v1.appStoreVersionLocalizations.id(localizationID).patch(updateRequest)
        _ = try await provider.request(apiRequest)
    }

    static func createLocalization(
        provider: APIProvider,
        versionID: String,
        locale: String,
        whatsNew: String
    ) async throws {
        let attributes = AppStoreVersionLocalizationCreateRequest.Data.Attributes(
            description: nil,
            locale: locale,
            keywords: nil,
            marketingURL: nil,
            promotionalText: nil,
            supportURL: nil,
            whatsNew: whatsNew
        )
        let versionRelationship = AppStoreVersionLocalizationCreateRequest.Data.Relationships.AppStoreVersion(
            data: .init(type: .appStoreVersions, id: versionID)
        )
        let relationships = AppStoreVersionLocalizationCreateRequest.Data.Relationships(
            appStoreVersion: versionRelationship
        )
        let data = AppStoreVersionLocalizationCreateRequest.Data(
            type: .appStoreVersionLocalizations,
            attributes: attributes,
            relationships: relationships
        )
        let createRequest = AppStoreVersionLocalizationCreateRequest(data: data)

        let apiRequest = APIEndpoint.v1.appStoreVersionLocalizations.post(createRequest)
        _ = try await provider.request(apiRequest)
        print("✅ Created \(locale) localization")
    }
}
