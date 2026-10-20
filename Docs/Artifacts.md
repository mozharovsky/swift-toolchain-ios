# Consumer artifacts

The producer packages its native compiler libraries, shared macro infrastructure, standard Swift,
Observation, and Foundation macros, and the open WASM SDK. Applications keep their project sources,
execution engines, and application-specific guest modules in their own packages.

`BuildMacros.cmake` reuses the compiler's existing SwiftSyntax modules. Those modules preserve their
source import names and carry distinct compiler ABI and linker names. The macro libraries therefore
share the existing support dylibs. Their upstream source remains in the ignored source cache.

The macro entry adapter preserves the upstream server's main-actor requirement. Background calls
synchronously use the main queue. Callers must keep that queue available while awaiting compiler
work. The adapter does not add process isolation or recover from native macro crashes.

The library-plugin provider links the compiler bridge's bundled-path validator. Both native
loaders open the canonical path returned by that shared policy. Macro implementations and the
in-process server use the flat framework layout described in [Compiler bridge](CompilerBridge.md).

## Foundation macros

`BuildMacros.cmake` also builds `FoundationMacros` from the swift-foundation commit tagged
`swift-6.4.0-RELEASE`, the release that produced the pinned SDK. The library implements
`#Predicate`, `#Expression`, and `#bundle`, which swift-foundation declares as external macros of
the `FoundationMacros` module. The standalone Swift release for macOS does not include this plugin.

The build compiles the upstream sources with `FOUNDATION_MACROS_LIBRARY`, which removes their
executable entry point, as in the plugin that Swift's Linux toolchains install. It keeps
swift-foundation's Swift 5 language mode and feature flags, so upstream warnings remain warnings.

Expansions follow the open-source configuration. They name `FoundationEssentials`, which the WASM
SDK provides, instead of Apple's `Foundation`.

`PredicateStringComparisons.patch` adds the string comparisons that Apple's predicate macro
accepts. These are `localizedStandardContains(_:)`, `localizedCompare(_:)`, and
`caseInsensitiveCompare(_:)`. Open-source Foundation has no expressions for them, so their
expansions call unqualified builders. A program that uses them must import a library that declares
these `PredicateExpressions` builders. The manifest records the patch as
`predicateStringComparisonsPatchSHA256`, and earlier releases omit the field.

Each slice of `MacroBuildSupport` carries the compiled sources in `Sources/FoundationMacros`.
Desktop tools that compile the same programs with the standalone release can build the plugin for
their own host from these files.

## Preparation

Start with completed device and simulator builds in one native compiler cache and the matching
Swift release toolchain. Set
`TOOLCHAIN_NATIVE_CACHE`, `TOOLCHAIN_BOOTSTRAP_ROOT`, `TOOLCHAIN_MACRO_OUTPUT`,
`TOOLCHAIN_SIMULATOR_MACRO_OUTPUT`, `TOOLCHAIN_SDK_ARCHIVE`, and `TOOLCHAIN_ARTIFACT_OUTPUT` to local
paths. The artifact output must be
a new ignored directory. An existing output is rejected so previously pinned archives remain intact.

```sh
mise exec -- cmake \
  -DTOOLCHAIN_NATIVE_CACHE="$TOOLCHAIN_NATIVE_CACHE" \
  -DTOOLCHAIN_BOOTSTRAP_ROOT="$TOOLCHAIN_BOOTSTRAP_ROOT" \
  -DTOOLCHAIN_MACRO_OUTPUT="$TOOLCHAIN_MACRO_OUTPUT" \
  -P CMake/BuildMacros.cmake
mise exec -- cmake \
  -DTOOLCHAIN_PLATFORM=simulator \
  -DTOOLCHAIN_NATIVE_CACHE="$TOOLCHAIN_NATIVE_CACHE" \
  -DTOOLCHAIN_BOOTSTRAP_ROOT="$TOOLCHAIN_BOOTSTRAP_ROOT" \
  -DTOOLCHAIN_MACRO_OUTPUT="$TOOLCHAIN_SIMULATOR_MACRO_OUTPUT" \
  -P CMake/BuildMacros.cmake
mise exec -- cmake \
  -DTOOLCHAIN_NATIVE_CACHE="$TOOLCHAIN_NATIVE_CACHE" \
  -DTOOLCHAIN_BOOTSTRAP_ROOT="$TOOLCHAIN_BOOTSTRAP_ROOT" \
  -DTOOLCHAIN_MACRO_OUTPUT="$TOOLCHAIN_MACRO_OUTPUT" \
  -DTOOLCHAIN_SIMULATOR_MACRO_OUTPUT="$TOOLCHAIN_SIMULATOR_MACRO_OUTPUT" \
  -DTOOLCHAIN_SDK_ARCHIVE="$TOOLCHAIN_SDK_ARCHIVE" \
  -DTOOLCHAIN_ARTIFACT_OUTPUT="$TOOLCHAIN_ARTIFACT_OUTPUT" \
  -DTOOLCHAIN_ARTIFACT_VERSION=0.1.0 \
  -P CMake/PackageArtifacts.cmake
swift run toolchain verify-artifact-manifest "$TOOLCHAIN_ARTIFACT_OUTPUT/ArtifactManifest.json"
mise exec -- cmake -DTOOLCHAIN_ARTIFACT_OUTPUT="$TOOLCHAIN_ARTIFACT_OUTPUT" \
  -DTOOLCHAIN_BOOTSTRAP_ROOT="$TOOLCHAIN_BOOTSTRAP_ROOT" \
  -P CMake/VerifyArtifacts.cmake
```

The compiler's post-link step writes `NativeArtifacts.json` with input identities, the native
compiler, and each native library's content hash. Macro preparation verifies that receipt and records its own linked inputs.
Packaging rejects missing, stale, or modified cache files before copying them. These receipts detect
cache integrity failures and are not signed build attestations. Archive builds disable automatic Git revision lookup so upstream tools cannot report a parent checkout as the compiler source. Exact upstream commits remain in the validated manifest.

The SDK archive must match the exact SHA-256 in `Toolchain.lock.json`. Packaging never reads an
installed Apple SDK as guest input. Xcode supplies the SDK only when compiling native libraries
and the small resource anchor.

The artifact manifest records `nativeCompiler`, the compiler identity and version that built the
native libraries. Packaging requires the device and simulator receipts to name the same compiler.
Manifests from releases before this record omit the field.

Artifact schema 2 requires device and simulator slices for every framework. Each slice records its
XCFramework identifier, native compiler triple, executable checksum, and executable size. Schema 1
metadata remains readable for existing device-only releases. The toolchain input lock and notice
index have independent schemas.

## Guest builtins

Swift's WASM SDK build configures the compiler-rt builtins without a CMake build type, so the SDK's
`libclang_rt.builtins-wasm32.a` is compiled without optimization. Guest programs call these
builtins for checked 64-bit multiplication, 128-bit integer division, the `long double` arithmetic
in `printf`, and other operations that WebAssembly lacks as instructions.

Packaging rebuilds that archive once from `compiler-rt` in the prepared llvm-project source. The
build keeps the upstream WASI options and adds the `Release` build type, which compiles with `-O3`.
It uses the bootstrap release's clang, whose version line must name the pinned llvm-project
revision. Packaging rejects LLVM patches that change compiler-rt, so the sources match that
revision. A source prefix map keeps the checkout path out of the archive's abort messages. The same
inputs therefore produce identical archive bytes. The build compiles about 150 small C files.

Each SDK slice replaces its archive only after a comparison with the bootstrap's LLVM tools. Both
archives must contain the same members and define the same global symbols with the same binding.
The rebuilt archive may drop external references but must not add any. The WASI target, the
archive's location in the payload, and the bridge ABI stay unchanged.

The manifest's `guestBuiltins` record names the payload path, the source revision, the build type,
and the compiler. It also records the replaced archive's digest, the packaged archive's digest, and
the number of defined symbols. Archive verification checks that digest and count in both SDK
slices. Manifests from earlier releases omit the record and ship the SDK's original archive. The
artifact schema version remains 2.

## Layout and validation

`Frameworks` separates device and simulator frameworks under their XCFramework slice identifiers.
`XCFrameworks` combines both arm64 environments with rewritten install names. `Archives` contains ZIP files for SwiftPM binary targets. `ArtifactManifest.json`
records configuration, patch, SDK, archive, and executable identities. The generated `Package.swift`
exposes one local `SwiftCompilerArtifacts` product for integration checks.

The manifest's `bridgeABI` repeats the version in the bridge header that the libraries were built
with. Verification requires the compiler bridge to export every entry point of that version,
including the completion functions of version 2 and the annotation function of version 3.

Packaging removes local symbol-table entries from staged framework copies with `strip -x`.
It checks that exported and imported global symbol names remain identical and that each binary's
size does not increase before replacing the staged file. Archive and executable checksums describe
the resulting binaries. Applications sign their embedded frameworks after packaging.

The manifest records `webAssemblyStackifyPatchSHA256` for the backported WebAssembly
stackification fix. Manifests from earlier releases omit it. Their compilers can produce wrong
overflow checks when a program enables the wide-arithmetic target feature.

The native profile records `restrictedSwiftPatchSHA256` and `restrictedLLVMPatchSHA256` with
`bundledMacroPatchSHA256`. Metadata validation requires the complete group when any member is
present and checks each digest's syntax. Earlier manifests can omit the group. Native receipts
also bind the profile source and configuration so packaging cannot reuse a broader compiler build.

`Development/MacroBuildSupport` separates native SwiftSyntax modules and matching support libraries
under `ios-arm64` and `ios-arm64-simulator`. Each directory includes compatibility metadata and open
C-shim headers for building additional bundled macro implementations. It also includes the
Foundation macro sources, which archive verification requires to match in both directories. Its ZIP
has a separate manifest record and is not part of the app's SwiftPM product. This lets a consumer
update its own native macro library without rebuilding the compiler or shipping build-only inputs
in the application.

`Licenses/NativeNotices.json` records additional license text selected from pinned native source
files. These entries include the xxHash, regular-expression, and Unicode conversion notices within
LLVM. Packaging verifies the source-file hash, complete declared comment range, selected-text hash,
and packaged notice before adding the entries to `NativeSources.json`. It removes comment delimiters
and one formatting space after each leading star, trims trailing line whitespace, and retains the
remaining text. Archive verification checks every copied notice in both native and target inventories.

The compiler framework declares file metadata access for container-scoped source and module loading.
Its disk-space declaration covers LLVM's cache pruning when the consumer enables an on-disk linker
cache. That path removes cached files based on available capacity before retaining more output.
These declarations require compiler inputs and caches to stay within the consumer's containers.
Consumers must keep capacity metadata and capacity-derived cache diagnostics on the device.

The iOS profile queries path locality through CoreFoundation resource metadata. Open descriptors
use `fgetattrlist` with only the returned-attribute mask and volume mount flags, so an unlinked file
retains its locality without requesting capacity. `AppleFileSystemMetadata.patch` selects that
adapter without changing LLVM's other platform implementations. A new native build is required
after this patch or its adapter changes. The native receipt and release manifest record the patch
identity. Older artifact manifests may omit that field.

SDK resources live inside `SwiftCompilerSDK.framework/Payload`. Serialized Swift modules are stored
as binary LZFSE resources because Xcode strips native-module filenames during artifact processing.
`Materialization.json` uses schema version 2 and declares `encoding` as `lzfse`. Each module record
contains its original path, encoded path, SHA-256, and `decodedByteCount`. A module must decode to
exactly that byte count, from 1 through 128 MiB, before the consumer checks its original digest.
Archive verification requires one complete LZFSE stream and rejects trailing encoded bytes.
Consumers that support only the earlier Base64 schema must update before adopting these artifacts.
Independent archive verification also accepts schema version 1 for existing Base64 releases.

Packaging and verification build the maintenance executable and use its `module-codec` command.
Both operations select Swift from `TOOLCHAIN_BOOTSTRAP_ROOT` and require the release recorded in
`Toolchain.lock.json` before building the codec.
Apple's Compression framework supplies LZFSE. This host-side operation does not rebuild the native
compiler or modify the module's restored bytes.
The remaining SDK contents keep the open toolchain layout. License texts and their source identities
are included in the same payload. Notice text preserves upstream terms and copyright statements. Trailing whitespace is normalized, and the index records both the original selected-text digest and the packaged-file digest.

Metadata verification checks names and version relationships. `VerifyArtifacts.cmake` independently
extracts archives, checks byte hashes, validates platform markers and the native dependency closure,
and restores each encoded SDK module to verify its original bytes. Packaging and archive validation
reject imports for process creation and instruction-cache or JIT operations that the current native
profile excludes. These checks permit the normal data-mapping and bundled-library APIs.
Application integration must also check the SDK after Xcode copies the frameworks.
The configuration-only fixture and macro threading
fixture do not claim execution of the iOS compiler.

A public release additionally needs reviewed archive contents and explicit publication. Preparation
does not upload binaries. Native library sizes exclude SDK resources and any cache a consumer creates.
Build success and metadata checks do not establish device execution or App Store acceptance.

The compiler's native SwiftSyntax support and library-plugin provider use prefixed framework and ABI
names. A consumer can therefore include the regular SwiftSyntax source package for parsing and
source preparation without colliding with compiler-internal targets or symbols.
