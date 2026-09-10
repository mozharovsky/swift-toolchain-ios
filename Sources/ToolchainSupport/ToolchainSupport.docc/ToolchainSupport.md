# ``ToolchainSupport``

ToolchainSupport validates build inputs and repository history before maintenance commands proceed.
The compiler host is an arm64 iOS device. Generated programs use the wasm32 WASI Preview 1 ABI.

The configuration validator checks fixed source revisions and the SDK archive identity. It does not
download those sources or prove that a compiler build succeeds. Repository policy rejects generated
artifacts from Git's source inventory. Commit validation is shared by the local hook and CI.

``ModuleCompression`` encodes serialized modules with Apple's LZFSE codec for artifact packaging.
Archive verification restores modules into a bounded output buffer before checking their digests.
Module conversion requires an Apple platform. Metadata and repository validation also run on Linux.

## Topics

### Build inputs

- ``ToolchainConfiguration``
- ``UpstreamSource``
- ``SDKArchive``

### Consumer artifacts

- ``ArtifactManifest``
- ``CompilerArtifact``
- ``MacroBuildSupport``
- ``ModuleCompression``

### Repository checks

- ``CommitMessage``
- ``RepositoryPolicy``
- ``ToolchainError``
