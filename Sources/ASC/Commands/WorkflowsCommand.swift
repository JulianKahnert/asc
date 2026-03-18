import ArgumentParser

/// Command group for Xcode Cloud workflow operations.
struct WorkflowsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workflows",
        abstract: "Manage Xcode Cloud workflows.",
        subcommands: [
            WorkflowsListCommand.self,
            WorkflowsTriggerCommand.self,
            WorkflowsStatusCommand.self
        ]
    )
}
