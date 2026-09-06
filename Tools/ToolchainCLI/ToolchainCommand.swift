import ArgumentParser

/// Maintenance entry point that leaves native compiler production an explicit later operation.
@main
struct ToolchainCommand: ParsableCommand {
    /// ArgumentParser exposes only implemented, bounded repository checks.
    static let configuration = CommandConfiguration(
        commandName: "toolchain",
        abstract: "Validate source inputs and repository metadata for the iOS Swift toolchain.",
        subcommands: [
            VerifyCommand.self,
            CheckCommitCommand.self,
            CheckHistoryCommand.self,
            CheckRepositoryCommand.self,
        ],
    )
}
