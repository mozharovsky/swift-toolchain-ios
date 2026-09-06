# Agent instructions

## Scope and structure

Task briefs and accepted design decisions define the current scope. This repository is a standalone
producer of Swift compiler libraries for iOS. Product-specific integrations belong to their consumers.
Private inputs, machine paths, credentials, and external private repository references stay outside
public files and release artifacts.

`AGENTS.md` is the single source of agent instructions. `CLAUDE.md` contains only `@AGENTS.md`.
Read `Docs/Conventions.md` before editing code or documentation.

`Sources/ToolchainSupport` owns typed build-input and repository validation. `Tools/ToolchainCLI`
owns argument parsing. `Sources/CompilerBridge` owns the C ABI and real frontend/LLD adapter.
CMake profiles and explicit production targets own upstream builds. `Toolchain.lock.json` records
immutable source revisions and archive checksums. Full compiler sources and generated artifacts
belong in `.cache`, `.build`, `Upstreams`, or `Artifacts`, which are ignored. Do not commit Apple SDK interfaces or SDK contents.

## Code quality

Use Swift 6 language mode, complete strict concurrency checking, and warnings as errors. Use typed
throws when the repository owns the closed error set. Do not force unwrap, force cast, use `try!`,
declare implicitly unwrapped optionals, or capture objects as `unowned`. Use swift-testing for tests.
Every handwritten Swift module has a DocC catalog and focused tests.

Document declarations at every access level. A type summary begins with a noun phrase. Each comment
states the purpose, the caller or subsystem that depends on it, and a fact absent from the signature.
Within a documented type, document every member. Trivial initializers follow SwiftLint's exception.
Write access modifiers only when changing Swift's default. Do not spell `internal`.

Use the pinned SwiftFormat and SwiftLint tools. C and C++ source follows `.clang-format` and uses an
explicit C ABI at the Swift boundary. Keep ownership, threading, and error propagation documented.
Generated files are regenerated from their owner rather than edited by hand.

## Dependencies and build work

ArgumentParser parses executable arguments. The pinned DocC plugin runs documentation checks.
Use swift-subprocess for future Swift child-process orchestration and swift-log if structured logging
is needed. Add a dependency only with an explicit role and a separately reviewable change. Do not
replace existing ecosystem functionality with a custom implementation.

Keep shell scripts as short sequences of external commands. Parsing, branching on command output,
and reusable maintenance logic belong in Swift. ShellCheck and shfmt check shell files.

Cheap checks must not trigger a full Swift or LLVM build. Heavy builds require an explicit command,
a recorded resource budget, and immutable input versions. Keep compiler-host and program-target
architectures separate. Report metadata validation, build success, simulator execution, physical
device execution, and distribution validation as distinct evidence.

## Verification

Run the checks that own the changed files before committing.

```sh
mise run check
```

This runs formatting and lint, repository and input verification, Swift build and tests, DocC, and
small native contract tests.
Compiler recipe changes additionally need their bounded configuration or native-build checks once
those recipes land. A source-only validation result is not proof of a rebuilt compiler.

## History and review

Commit subjects and pull request titles use `type(scope): subject` and contain fewer than 72
characters. Allowed types are `feat`, `fix`, `docs`, `refactor`, `test`, `perf`, `ci`, `build`, and
`chore`. Scopes are `compiler`, `backend`, `bridge`, `sdk`, `macros`, `tools`, `ci`, and `docs`.
Each commit explains why the change is needed and includes `Signed-off-by` in its final trailer block.
Other trailers may follow the sign-off within that block.

Use small stacked changes through `gh stack` when publishing a pull request stack. Every branch
must pass its applicable checks. A human performs merges. Follow the pull request template.
Resolve both inline review threads and findings in review summaries. Fix review findings with new
signed commits rather than amending existing commits. Do not enable paid review usage without
authorization.

Creating commits, publishing branches or releases, changing repository settings, contacting others,
and operating physical devices follow the task's explicit authorization. Do not infer publication
permission from a request to prepare local changes.

## Public artifacts

Keep release jobs separate from untrusted pull request code. Pin GitHub Actions by full commit SHA.
Do not expose signing or publishing credentials to pull request jobs. Do not automatically run
untrusted changes on a maintainer's workstation.

Release metadata records source revisions, the compiler host, program target, SDK identity, bridge
ABI, archive checksums, licenses, and tested platforms. Consumers choose an immutable release.
SDK resources are compiler inputs and are not native libraries to link into the host executable.
Do not claim App Store approval from compiler build or device execution alone.
