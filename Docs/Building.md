# Building the compiler libraries

The producer uses CMake and Ninja. Source identities and archive SHA-256 values come from
`Toolchain.lock.json`. The generated program target is wasm32 WASI Preview 1. The compiler itself
runs on an arm64 iOS device with the deployment version recorded in the lock file.

## Bounded repository checks

The standard check includes the Swift maintenance package and small native bridge contract tests.
It does not acquire or build the upstream compiler.

```sh
mise install --locked
mise run check
```

Run only the native contract checks with `mise run native-check`. They use sanitizers on the build
machine. On macOS they also check C and C++ formatting with the selected Xcode clang-format.

## Native production graph

The initial producer requires an Apple silicon Mac, the selected Xcode SDK, and the Swift release
matching `swiftVersion` in the lock file. `TOOLCHAIN_BOOTSTRAP_ROOT` is that release toolchain's
`usr` directory. The repository does not choose or replace the machine's Xcode installation.

Configure the explicit compiler targets after selecting those tools. The command below uses the
caller's `TOOLCHAIN_BOOTSTRAP_ROOT` environment variable as an input path.

```sh
mise exec -- cmake -S . -B .cache/compiler-plan -G Ninja \
  -DBUILD_TESTING=OFF \
  -DTOOLCHAIN_ENABLE_COMPILER_BUILD=ON \
  -DTOOLCHAIN_BOOTSTRAP_ROOT="$TOOLCHAIN_BOOTSTRAP_ROOT" \
  -DTOOLCHAIN_BUILD_JOBS=4
```

Configuration validates the bootstrap release and creates the graph. It does not download sources
or start compiler builds. The default build also leaves those explicit targets untouched.

Prepare source archives separately. CMake reuses a downloaded archive only when its SHA-256 matches.
Each checkout is isolated by source identity. The Swift source identity also includes the patch hash.

```sh
mise exec -- cmake --build .cache/compiler-plan --target toolchain-sources --parallel 2
```

The source target extracts Swift, LLVM, SwiftSyntax, cmark, and string-processing archives and applies
`DisableImmediateExecution.patch`. It does not fetch a consumer project or copy an Apple SDK.

The following is a large native build. Establish a CPU, disk, and memory budget before running it.
Four jobs are allowed inside the active stage, native stages run in sequence, and LLVM and Swift
links use one slot. This command is not called by normal pull request checks.

```sh
mise exec -- cmake --build .cache/compiler-plan --target toolchain-compiler --parallel 1
```

The stages build host TableGen tools, required iOS LLVM/Clang/LLD libraries, the static iOS cmark
library, and the Swift frontend with the real bridge. Native build directories are keyed by the
input and patch identities. Repeated explicit builds let the underlying build systems check source
and configuration changes.

The main output is `libSwiftCompilerBridge.dylib` under the generated `swift-ios/lib` directory.
Compiler support libraries are under `swift-ios/lib/swift/host/compiler`. The initial target does not
package
XCFrameworks, install a target WASM SDK into an application, or produce the native macro-server
bundle. Those artifact composition steps follow after the library build is validated.

## Evidence boundaries

The source target and patch application can be validated without compiling LLVM. Contract tests
exercise the bridge with a test backend. A real backend object build requires matching generated
upstream headers, and a library link additionally requires the native dependency archives.

A completed clean build of these recipes, execution on a physical iPhone, and validation of a
redistributable artifact are separate results. Existing compatible libraries can help check a small
bridge change, but their reuse is not evidence of a clean build from these recipes. Prefix maps
reduce machine-path exposure. Release archives still require an explicit content and symbol audit.
