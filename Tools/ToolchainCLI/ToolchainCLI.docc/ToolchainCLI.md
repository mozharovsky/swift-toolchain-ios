# ``ToolchainCLI``

ToolchainCLI provides the `toolchain` maintenance executable. ArgumentParser validates command-line
input. The commands inspect the toolchain lock file, commit messages, and Git's source inventory.
They do not fetch upstream sources, build the compiler, or publish releases.

`verify` validates source and SDK identities. `check-commit-message` reads Git's message file.
`check-history` consumes complete NUL-separated commit messages. `check-repository` consumes
NUL-separated repository-relative paths.
