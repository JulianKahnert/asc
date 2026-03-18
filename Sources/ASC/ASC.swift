import ArgumentParser

// Renamed from ASC to ASCMain so the module can be imported as a library
// by the ASCExecutable target (which calls ASCMain.main()) and by tests.
public struct ASCMain: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "asc",
        abstract: "AppStoreConnect Helper - Manage your App Store Connect versions.",
        subcommands: [
            InitCommand.self,
            ClearCommand.self,
            AppsCommand.self,
            VersionsCommand.self,
            WorkflowsCommand.self
        ]
    )
}
