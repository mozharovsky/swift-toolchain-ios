# ``ToolchainSupport``

ToolchainSupport validates build inputs and repository history before maintenance commands proceed.
Native compiler slices target arm64 iOS devices and Apple silicon simulators. Generated programs
use the wasm32 WASI Preview 1 ABI.

The configuration validator checks fixed source revisions and the SDK archive identity. It does not
download those sources or prove that a compiler build succeeds. Repository policy rejects generated
artifacts from Git's source inventory. Commit validation is shared by the local hook and CI.

``PayloadCompression`` encodes SDK payload files with Apple's LZFSE codec for artifact packaging.
Archive verification restores files into a bounded output buffer before checking their digests.
Payload conversion requires an Apple platform. Metadata and repository validation also run on Linux.

## Topics

### Build inputs

- ``ToolchainConfiguration``
- ``UpstreamSource``
- ``SDKArchive``

### Consumer artifacts

- ``ArtifactManifest``
- ``CompilerArtifact``
- ``CompilerArtifactSlice``
- ``GuestBuiltins``
- ``GuestFoundation``
- ``MacroBuildSupport``
- ``PayloadCompression``

### Repository checks

- ``CommitMessage``
- ``RepositoryPolicy``
- ``ToolchainError``
