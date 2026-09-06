# Toolchain boundaries

The planned producer builds native Swift frontend and LLVM libraries for an arm64 iOS application.
The WebAssembly backend and LLD produce a statically linked `wasm32-unknown-wasip1` program. The open
WASM SDK supplies the guest standard library, runtime archives, and supported Foundation components.
These guest archives are compiler input data. They are not arm64 libraries.

`Toolchain.lock.json` pins source commits and the official SDK archive. The verifier checks source
and archive
identities and the target relationship. CMake owns source preparation and the explicit native build
graph. Artifact packaging and publication remain separate work.

## Producer and consumer

The producer owns upstream patches, native compiler assembly, generic macro infrastructure, SDK
packaging, and release provenance. An embedding application owns its source editor, project graph,
execution engine, resources, and any product-specific guest modules.

A future artifact release will use versioned XCFramework archives and SHA-256 checksums. It must
record the bridge ABI, native compiler revision, target SDK, notices, and tested platforms. Source
revisions and an archive checksum do not by themselves prove a reproducible native build.

## Runtime constraints

The compiler runs inside its embedding process. Ordinary source diagnostics and internal compiler
failures have different recovery contracts. LLVM fatal handlers do not generally convert assertions
into recoverable errors. Native cancellation and memory limits require their own validation.

The initial intended host is an arm64 iOS device. Simulator support is separate work. No device
support or App Store approval is established by this repository's maintenance tests.

## Next implementation work

Validate a complete native build from the pinned source archives, then prepare versioned release
artifacts. The bridge and configuration recipes are checked in with bounded contract checks. Keep
full upstream trees,
SDK downloads, native build products, and release archives in ignored storage.
