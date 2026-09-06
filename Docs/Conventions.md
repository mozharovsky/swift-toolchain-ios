# Conventions

## Prose

Write plain English in short complete sentences. Use paragraphs for reasoning and lists for parallel
items or procedures. Headings stop at level three. Avoid colon-led fragments, semicolon chains,
em dashes, contrast slogans, filler, rhetorical questions, and marketing claims.

Documentation describes implemented behavior. Plans and limitations are identified as such. Keep
private design inputs and machine-specific paths outside public documentation. Preserve upstream
copyright and license attribution when adapting source.

A documentation comment starts with a standalone summary. A type summary begins with a noun phrase.
Explain the declaration's purpose and which caller or subsystem depends on it. Include a contract,
ownership fact, invariant, unit, lifecycle rule, or failure condition that its signature does not
already express. Never restate the name and type as its documentation.

Use DocC parameter, return, and throw fields when they clarify a contract. Comments on implementation
choices explain why the choice exists. Document declarations at all access levels and every member
of a documented type. Trivial initializers follow the configured SwiftLint exception.

## Implementation

Swift uses language mode 6 and complete concurrency checking. Every module treats warnings as errors.
Use typed throws for closed error sets. Use swift-testing and focused tests that expose meaningful
failure or compatibility boundaries. Every handwritten Swift module has a DocC catalog.

Do not use force unwraps, forced casts, `try!`, implicitly unwrapped optionals, or `unowned` captures.
State invariants with `guard` and typed errors. Keep access modifiers explicit only when they change
the default. Files open with imports unless the file format requires a leading marker.

Use ArgumentParser for command-line syntax. Use the pinned DocC plugin for documentation generation.
Future subprocess work uses swift-subprocess. Future structured logging uses swift-log. Dependencies
arrive with a documented role in their own reviewable change. Quality tools are pinned development
tools rather than runtime dependencies.

C and C++ follow the checked-in LLVM-based formatter configuration. A C ABI must state who owns every
buffer and whether compiler state remains reusable after failure. Keep upstream changes in small
patches with their source revision and reason. Do not copy an upstream repository into this one.

Shell is limited to short build and hook adapters. Reusable logic and parsed command output belong
in Swift. Shell files pass ShellCheck and shfmt without suppressions added to make a failure pass.

## Validation and CI

`mise run check` is the local entry point. It runs checks in sequence so SwiftPM operations do not
contend over one scratch directory. CI uses separate jobs for quality, Linux build and tests, macOS
build and tests, documentation, and pull request commit metadata.

SwiftFormat, SwiftLint, ShellCheck, and shfmt use pinned versions and archive identities in `mise.lock`.
The complete mise installation and download cache is retained together in CI. A tool cache hit must
not depend on undeclared files outside that cache. Job timeouts bound a failure rather than hide
repeated network retries.

Pull request checks do not build Swift or LLVM. Compiler production needs a separate workflow with
explicit inputs, budgets, and release authorization. A reviewed build recipe and a completed clean
compiler build are separate results. Platform support requires execution evidence for that platform.

The intended required check names are `Format and lint`, `Linux build and tests`, `macOS build and
tests`, `Documentation`, and `Commit policy`. Repository rulesets are configured separately from the
workflow files after these checks have run on GitHub. CodeRabbit configuration does not install or
authorize the GitHub application.

## Contributions

Use scoped Conventional Commits under 72 characters with a body explaining the reason and a final
DCO sign-off. Review fixes use new commits. Pull request descriptions explain the resulting behavior
and validation. Record unverified platforms and deferred work without implying those checks passed.
Humans merge changes after required checks and review findings are resolved.
