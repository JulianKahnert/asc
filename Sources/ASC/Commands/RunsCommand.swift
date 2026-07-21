import ArgumentParser

/// Command group for Xcode Cloud build runs (the executions of a workflow).
///
/// Mirrors `gh run`: `workflows` manages the workflow *definitions*, `runs`
/// works with their individual *executions* and their artifacts.
struct RunsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runs",
        abstract: "Inspect Xcode Cloud build runs and their artifacts.",
        subcommands: [
            RunsListCommand.self,
            RunsViewCommand.self,
            RunsDownloadCommand.self
        ]
    )
}
