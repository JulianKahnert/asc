import ArgumentParser

/// Command group for app-related operations.
struct AppsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "Manage apps in your App Store Connect account.",
        subcommands: [
            AppsListCommand.self
        ]
    )
}
