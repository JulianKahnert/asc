import ArgumentParser

/// Command group for version lifecycle operations.
struct VersionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "versions",
        abstract: "Manage app versions in App Store Connect.",
        subcommands: [
            VersionCreateCommand.self,
            VersionShowCommand.self,
            VersionSelectBuildCommand.self,
            VersionSubmitCommand.self
        ]
    )
}
