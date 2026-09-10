# ``ToolchainCLI``

ToolchainCLI provides the `toolchain` maintenance executable. ArgumentParser validates command-line
input. The commands inspect the toolchain lock file, commit messages, and Git's source inventory.
They do not fetch upstream sources, build the compiler, or publish releases.

`verify` validates source and SDK identities. `check-commit-message` reads Git's message file.
`check-history` consumes complete NUL-separated commit messages. An empty stream succeeds because
the selected Git range may contain only exempt merge commits. Empty commit records still fail the
message policy. `Scripts/check-history.sh` selects
non-merge commits from every parent history before invoking this command. `check-repository`
consumes NUL-separated repository-relative paths.

`verify-artifact-manifest` checks release identities, archive basenames, required components, and
digest formatting. It does not inspect ZIP contents or execute a native compiler.
