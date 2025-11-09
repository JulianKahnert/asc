//
//  SubmitCommand.swift
//  ASC
//
//  Created by Julian Kahnert on 09.11.25.
//

import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

struct SubmitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit",
        abstract: "Submit current version for Apple review"
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect")
    var appID: String

    @Option(help: "Platform to submit (ios or macos)")
    var platform: String = "ios"

    func run() async throws {
        // Parse platform
        let platformValue: AppStoreVersionCreateRequest.Data.Attributes.Platform
        switch platform.lowercased() {
        case "ios":
            platformValue = .iOS
        case "macos":
            platformValue = .macOS
        default:
            throw ValidationError("Invalid platform. Use 'ios' or 'macos'")
        }

        // Retrieve credentials from keychain
        let service = KeychainHelper.service

        guard let issuerID = KeychainHelper.getKeychainItem(service: service, account: "issuerID") else {
            throw ValidationError("issuerID not found in keychain. Please run 'asc init' first.")
        }

        guard let keyID = KeychainHelper.getKeychainItem(service: service, account: "keyID") else {
            throw ValidationError("keyID not found in keychain. Please run 'asc init' first.")
        }

        guard let privateKey = KeychainHelper.getKeychainItem(service: service, account: "privateKey") else {
            throw ValidationError("privateKey not found in keychain. Please run 'asc init' first.")
        }

        // Configure authentication
        let configuration = APIConfiguration(
            issuerID: issuerID,
            privateKeyID: keyID,
            privateKey: privateKey
        )

        let provider = APIProvider(configuration: configuration)

        // Check if appID is a bundle ID (contains dots) and convert to App ID if needed
        var resolvedAppID = appID
        if appID.contains(".") {
            print("🔍 Resolving bundle ID '\(appID)' to App ID...")
            resolvedAppID = try await resolveAppID(provider: provider, bundleID: appID)
        }

        // Find the version ready for submission
        print("🔍 Finding version ready for submission...")
        let versionID = try await findPreparedVersion(provider: provider, appID: resolvedAppID, platform: platformValue)

        guard let versionID = versionID else {
            throw ValidationError("No version found in PREPARE_FOR_SUBMISSION state")
        }

        print("📤 Submitting version for review...")
        try await submitVersion(provider: provider, versionID: versionID)

        print("✅ Successfully submitted version for review")
    }

    private func resolveAppID(provider: APIProvider, bundleID: String) async throws -> String {
        let endpoint: APIEndpoint<AppsResponse> = .apps(
            select: [.apps([.name, .bundleId])],
            filters: [.bundleId([bundleID])],
            limits: [.apps(1)]
        )

        return try await withCheckedThrowingContinuation { continuation in
            provider.request(endpoint) { (result: Result<AppsResponse, Error>) in
                switch result {
                case .success(let response):
                    guard let app = response.data.first else {
                        continuation.resume(throwing: ValidationError("No app found with bundle ID '\(bundleID)'"))
                        return
                    }
                    continuation.resume(returning: app.id)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func findPreparedVersion(
        provider: APIProvider,
        appID: String,
        platform: AppStoreVersionCreateRequest.Data.Attributes.Platform
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            let endpoint: APIEndpoint<AppStoreVersionsResponse> = .appStoreVersions(
                ofAppWithId: appID,
                fields: [.appStoreVersions([.versionString, .platform, .appStoreState])],
                limit: 10
            )

            provider.request(endpoint) { (result: Result<AppStoreVersionsResponse, Error>) in
                switch result {
                case .success(let response):
                    let preparedVersion = response.data
                        .filter { $0.attributes?.platform?.rawValue == platform.rawValue }
                        .first { version in
                            version.attributes?.appStoreState?.rawValue == "PREPARE_FOR_SUBMISSION"
                        }

                    if let version = preparedVersion, let versionString = version.attributes?.versionString {
                        print("  Found version: \(versionString)")
                        continuation.resume(returning: version.id)
                    } else {
                        continuation.resume(returning: nil)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func submitVersion(provider: APIProvider, versionID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let endpoint = APIEndpoint.create(appStoreVersionSubmissionForVersionWithId: versionID)

            provider.request(endpoint) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
