# ``ToolchainCLI``

ToolchainCLI provides the `toolchain` maintenance executable. ArgumentParser validates command-line
input. The commands inspect the toolchain lock file, commit messages, and Git's source inventory.
Module conversion is available for artifact packaging on Apple platforms. Native compiler production
and release publication use separate commands outside this executable.

`verify` validates source and SDK identities. `check-commit-message` reads Git's message file.
`check-history` consumes complete NUL-separated commit messages. An empty stream succeeds because
the selected Git range may contain only exempt merge commits. Empty commit records still fail the
message policy. `Scripts/check-history.sh` selects
non-merge commits from every parent history before invoking this command. `check-repository`
consumes NUL-separated repository-relative paths.

`verify-artifact-manifest` checks release identities, archive basenames, required components, and
digest formatting. It does not inspect ZIP contents or execute a native compiler.

`module-codec compress` reads serialized module bytes and writes a new LZFSE file.
`module-codec decompress` restores a compressed file and requires `--decoded-bytes` to declare the
exact output size, from 1 through 128 MiB. Both operations accept input and output paths as positional
arguments and refuse to overwrite an existing output. The archive verifier checks the restored
module's digest separately.
