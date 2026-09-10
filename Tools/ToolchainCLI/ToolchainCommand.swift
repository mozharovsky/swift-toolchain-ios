import ArgumentParser

/// The command-line entry point used by packaging and repository checks for bounded maintenance.
@main
struct ToolchainCommand: ParsableCommand {
    /// ArgumentParser keeps bounded maintenance separate from native compiler production.
    static let configuration = CommandConfiguration(
        commandName: "toolchain",
        abstract: "Validate and prepare inputs for the iOS Swift toolchain.",
        subcommands: [
            VerifyCommand.self,
            VerifyArtifactManifestCommand.self,
            ModuleCodecCommand.self,
            CheckCommitCommand.self,
            CheckHistoryCommand.self,
            CheckRepositoryCommand.self,
        ],
    )
}
