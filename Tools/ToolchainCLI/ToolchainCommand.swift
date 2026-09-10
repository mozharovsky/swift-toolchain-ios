import ArgumentParser

/// Maintenance entry point for validated build inputs, repository history, and module resources.
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
