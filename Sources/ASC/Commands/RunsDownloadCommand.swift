import ArgumentParser
import AppStoreConnect_Swift_SDK
import Foundation

/// Downloads the artifacts of a build run (`gh run download`).
struct RunsDownloadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Download a build run's artifacts (logs, result bundles, archives …).",
        discussion: """
            Fetches fresh pre-signed URLs from the API and downloads the matching
            artifacts to a local directory, so other clients can debug the build.
            Without --type, all artifacts are downloaded.

            Artifact types: LOG_BUNDLE, RESULT_BUNDLE, ARCHIVE, ARCHIVE_EXPORT,
            TEST_PRODUCTS, XCODEBUILD_PRODUCTS, STAPLED_NOTARIZED_ARCHIVE.

            Examples:
              $ asc runs download com.example.app 42 --type LOG_BUNDLE
              $ asc runs download com.example.app 42 --output ./ci-logs
              $ asc runs download com.example.app 42 --json
            """
    )

    @Argument(help: "The App ID or Bundle ID from App Store Connect.")
    var appID: String

    @Argument(help: "The build run number (as shown by 'asc runs list').")
    var number: Int

    @Option(help: "Disambiguate the build number to a specific workflow.")
    var workflow: String?

    @Option(help: "Only download artifacts of this type (e.g. LOG_BUNDLE).")
    var type: String?

    @Option(help: "Only download artifacts of this action (e.g. Build, Test).")
    var action: String?

    @Option(help: "Directory to download artifacts into.")
    var output: String = "."

    @Flag(name: .long, help: "Output the result as JSON.")
    var json = false

    /// Describes one downloaded artifact for `--json` output.
    struct DownloadedArtifact: Codable {
        let fileName: String
        let fileType: String?
        let fileSize: Int?
        let path: String
    }

    func run() async throws {
        let typeFilter = try type.map { try CiArtifact.Attributes.FileType.parse($0) }

        let provider = try KeychainHelper.createAPIProvider()
        let resolvedAppID = try await KeychainHelper.resolveAppID(provider: provider, appIDOrBundleID: appID)
        let productID = try await KeychainHelper.getCiProductID(provider: provider, appID: resolvedAppID)

        var workflowID: String?
        if let workflow {
            workflowID = try await RunsLogic.resolveWorkflowID(provider: provider, productID: productID, name: workflow)
        }

        let run = try await RunsLogic.resolveRun(
            provider: provider,
            productID: productID,
            workflowID: workflowID,
            number: number
        )

        let actions = try await RunsLogic.fetchActions(
            provider: provider,
            runID: run.id,
            query: .init(actionFilter: action, includeArtifacts: true)
        )

        let artifacts = actions.flatMap { $0.artifacts }.filter { artifact in
            guard let typeFilter else { return true }
            return artifact.fileType == typeFilter.rawValue
        }

        if artifacts.isEmpty {
            if json {
                try JSONOutput.emit([DownloadedArtifact]())
            } else {
                print("No matching artifacts found for build #\(number).")
            }
            return
        }

        let directory = URL(fileURLWithPath: output, isDirectory: true)
        let downloaded = try await downloadAll(artifacts, to: directory, quiet: json)

        if json {
            try JSONOutput.emit(downloaded)
        } else {
            for item in downloaded {
                print("✅ \(item.path)")
            }
        }
    }

    /// Downloads each artifact into `directory`, returning the saved files.
    private func downloadAll(
        _ artifacts: [ArtifactInfo],
        to directory: URL,
        quiet: Bool
    ) async throws -> [DownloadedArtifact] {
        var downloaded: [DownloadedArtifact] = []
        for artifact in artifacts {
            guard let urlString = artifact.downloadUrl else { continue }
            let fileName = artifact.fileName ?? "\(artifact.fileType ?? "artifact")-\(artifact.id)"

            if !quiet { print("Downloading \(fileName)…") }

            let path = try await RunsLogic.downloadArtifact(
                from: urlString,
                fileName: fileName,
                to: directory
            )
            downloaded.append(DownloadedArtifact(
                fileName: fileName,
                fileType: artifact.fileType,
                fileSize: artifact.fileSize,
                path: path.path
            ))
        }
        return downloaded
    }
}
