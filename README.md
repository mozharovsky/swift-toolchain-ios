# swift-toolchain-ios

Experimental Swift toolchain builds that run on iOS and produce WebAssembly.

The intended compiler runs natively inside an arm64 iOS application. Its frontend and LLVM backend
produce `wasm32-unknown-wasip1` code, which LLD links against the open Swift SDK for WebAssembly.
The application that embeds the compiler supplies its own execution environment.

The repository contains a native C ABI bridge, pinned CMake build recipes, and tested maintenance
tools. Compiler production is an explicit operation. There is no published compiler artifact release
yet. Passing repository checks does not establish a clean compiler build, device execution, or
App Store acceptance.

## Development

Maintenance tools require Swift 6.3 or later on macOS or Linux. Native iOS compiler production will
require macOS and the selected Xcode SDK. The build input file records the compiler host separately
from the generated program target.

```sh
mise install --locked
mise run check
swift run toolchain verify
```

`mise run check` runs formatting, lint, source-inventory checks, Swift tests, DocC, and native
contract tests.
It does not download or build Swift or LLVM. See [Contributing](CONTRIBUTING.md) for local hooks and
[Conventions](Docs/Conventions.md) for the code and review standards.

## Repository layout

`Toolchain.lock.json` identifies upstream commits and the target SDK archive. `Sources/ToolchainSupport`
contains validation shared by the command-line tool and tests. `Tools/ToolchainCLI` exposes the
maintenance commands. `Tests` contains focused failure and compatibility checks. The C ABI and real
compiler adapter live in `Sources/CompilerBridge`.

Compiler source checkouts, SDK contents, build directories, and release archives belong in ignored
storage. [Building](Docs/Building.md) describes source preparation and explicit native builds.
[Compiler bridge](Docs/CompilerBridge.md) describes ownership and recovery.
[Toolchain boundaries](Docs/Toolchain.md) describes the intended producer and artifact split.

## Licensing

Repository-authored code uses Apache-2.0. The compiler, SDK, and other upstream components retain
their own licenses and exceptions. Their identifiers are recorded beside the pinned inputs.
Distributable artifacts must carry the notices required by every included component.
