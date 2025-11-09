//
//  VersionCommand.swift
//  ASC
//
//  Created by Julian Kahnert on 07.11.25.
//

import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

struct VersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Create or update an app version with release notes"
    )

    @Argument(help: "The App ID from App Store Connect")
    var appID: String

    @Argument(help: "The version string (e.g., 1.0.0)")
    var version: String

    @Option(name: .customLong("hintGerman"), help: "German release notes")
    var hintGerman: String?

    @Option(name: .customLong("hintEnglish"), help: "English release notes")
    var hintEnglish: String?

    @Option(name: .customLong("hint"), help: "JSON string with 'german' and 'english' keys containing release notes")
    var hintJSON: String?

    func run() async throws {
        // Parse hints from either JSON or individual options
        let (germanHint, englishHint) = try parseHints()

        let provider = try KeychainHelper.createAPIProvider()
        print("🔑 Retrieved credentials from keychain")

        // Check if appID is a bundle ID (contains dots) and convert to App ID if needed
        var resolvedAppID = appID
        if appID.contains(".") {
            print("🔍 Resolving bundle ID '\(appID)' to App ID...")
            resolvedAppID = try await KeychainHelper.resolveAppID(provider: provider, bundleID: appID)
            print("✅ Found App ID: \(resolvedAppID)")
        }

        print("📱 Creating/updating version \(version) for app \(resolvedAppID)...")

        do {
            // Try to create or find existing iOS version
            print("📱 Creating/finding iOS version...")
            let iOSVersionID = try await createOrFindVersion(
                provider: provider,
                appID: resolvedAppID,
                versionString: version,
                platform: .ios
            )
            print("✅ iOS version ID: \(iOSVersionID)")

            // Try to create or find existing macOS version
            print("💻 Creating/finding macOS version...")
            let macOSVersionID = try await createOrFindVersion(
                provider: provider,
                appID: resolvedAppID,
                versionString: version,
                platform: .macOs
            )
            print("✅ macOS version ID: \(macOSVersionID)")

            // Update localizations for iOS
            print("📝 Updating iOS release notes...")
            try await updateOrCreateLocalization(
                provider: provider,
                versionID: iOSVersionID,
                locale: "de-DE",
                whatsNew: germanHint
            )
            try await updateOrCreateLocalization(
                provider: provider,
                versionID: iOSVersionID,
                locale: "en-US",
                whatsNew: englishHint
            )

            // Update localizations for macOS
            print("📝 Updating macOS release notes...")
            try await updateOrCreateLocalization(
                provider: provider,
                versionID: macOSVersionID,
                locale: "de-DE",
                whatsNew: germanHint
            )
            try await updateOrCreateLocalization(
                provider: provider,
                versionID: macOSVersionID,
                locale: "en-US",
                whatsNew: englishHint
            )

            print("✅ Successfully updated versions with release notes")
        } catch {
            print("❌ Error: \(error)")
            throw error
        }
    }

    private func parseHints() throws -> (german: String, english: String) {
        // If JSON hint is provided, parse it
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

        // Otherwise, use individual options
        guard let german = hintGerman, let english = hintEnglish else {
            throw ValidationError("Either provide --hint with JSON, or both --hintGerman and --hintEnglish")
        }

        return (german, english)
    }

    private func createOrFindVersion(
        provider: APIProvider,
        appID: String,
        versionString: String,
        platform: Platform
    ) async throws -> String {
        // Try to create the version
        do {
            let versionID = try await createVersion(
                provider: provider,
                appID: appID,
                versionString: versionString,
                platform: platform
            )
            return versionID
        } catch {
            // If it fails with 409 DUPLICATE, try to find the existing version
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

            // Check if it's the "cannot create in current state" error
            if errorString.contains("409") && errorString.contains("You cannot create a new version of the App in the current state") {
                print("   ⚠️  Cannot create new version - an active version already exists")
                print("   🔍 Finding active version to update...")

                // Find the current active version
                let activeVersion = try await findActiveVersion(
                    provider: provider,
                    appID: appID,
                    platform: platform
                )

                if let activeVersion = activeVersion {
                    print("   📝 Found active version \(activeVersion.versionString) (ID: \(activeVersion.id))")
                    print("   🔄 Updating version number from \(activeVersion.versionString) to \(versionString)...")

                    // Update the version number
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

    private func createVersion(
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

    private func findExistingVersion(
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

        // Filter matching versions
        let matchingVersions = response.data.filter {
            $0.attributes?.versionString == versionString &&
            $0.attributes?.platform == platform
        }

        guard !matchingVersions.isEmpty else {
            throw ValidationError("Could not find existing version \(versionString) for platform \(platform.rawValue)")
        }

        // Prioritize by state: active states first
        let priorityStates = [
            "PREPARE_FOR_SUBMISSION",
            "WAITING_FOR_REVIEW",
            "IN_REVIEW",
            "PENDING_DEVELOPER_RELEASE",
            "DEVELOPER_REJECTED",
            "REJECTED"
        ]

        // Find version with highest priority state
        for state in priorityStates {
            if let version = matchingVersions.first(where: {
                $0.attributes?.appStoreState?.rawValue == state
            }) {
                return version.id
            }
        }

        // Fallback: return first matching version (e.g., READY_FOR_SALE)
        if let version = matchingVersions.first {
            return version.id
        } else {
            throw ValidationError("Could not find existing version \(versionString) for platform \(platform.rawValue)")
        }
    }

    private func findActiveVersion(
        provider: APIProvider,
        appID: String,
        platform: Platform
    ) async throws -> (id: String, versionString: String)? {
        var parameters = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters()
        parameters.fieldsAppStoreVersions = [.versionString, .platform, .appStoreState]
        parameters.limit = 10

        let request = APIEndpoint.v1.apps.id(appID).appStoreVersions.get(parameters: parameters)

        do {
            let response = try await provider.request(request)

            // Find the first version that is in an active state (PREPARE_FOR_SUBMISSION, WAITING_FOR_REVIEW, IN_REVIEW)
            let activeStates = ["PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"]
            let activeVersion = response.data
                .filter { $0.attributes?.platform == platform }
                .first { version in
                    guard let state = version.attributes?.appStoreState?.rawValue else { return false }
                    return activeStates.contains(state)
                }

            if let version = activeVersion, let versionString = version.attributes?.versionString {
                return (id: version.id, versionString: versionString)
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }

    private func updateVersionNumber(
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

    private func updateOrCreateLocalization(
        provider: APIProvider,
        versionID: String,
        locale: String,
        whatsNew: String
    ) async throws {
        // First, try to get existing localizations
        let existingLocalizations = try await listLocalizations(provider: provider, versionID: versionID)

        // Check if this locale already exists
        if let existingLocalization = existingLocalizations.first(where: { $0.locale == locale }) {
            // Update existing localization
            try await updateLocalization(
                provider: provider,
                localizationID: existingLocalization.id,
                whatsNew: whatsNew
            )
            print("✅ Updated \(locale) localization")
        } else {
            // Create new localization
            try await createLocalization(
                provider: provider,
                versionID: versionID,
                locale: locale,
                whatsNew: whatsNew
            )
        }
    }

    private func listLocalizations(
        provider: APIProvider,
        versionID: String
    ) async throws -> [(id: String, locale: String)] {
        let request = APIEndpoint.v1.appStoreVersions.id(versionID).appStoreVersionLocalizations.get()
        let response = try await provider.request(request)

        let localizations = response.data.map { localization in
            (
                id: localization.id,
                locale: localization.attributes?.locale ?? ""
            )
        }
        return localizations
    }

    private func updateLocalization(
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

    private func createLocalization(
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
