# Contributing

Use Swift 6.3 or later. macOS maintenance checks use Xcode 26.6 in CI. Linux checks use the pinned
Swift 6.3.2 container. Native compiler production will be a separate operation from routine checks.

## Local setup

Install mise through its [official installation instructions](https://mise.jdx.dev/installing-mise.html).
Review the repository configuration before trusting it. Then install the locked quality tools.

```sh
mise trust
mise install --locked
git config --local core.hooksPath Scripts/Hooks
mise run check
```

The hook setting applies only to this checkout. The pre-commit hook checks formatting and lint without
changing files. Run `mise run format` to apply formatting and inspect the resulting diff. Repository
checks include untracked authored files and exclude ignored upstream caches.

SwiftPM dependencies are pinned in Package.swift and Package.resolved. The maintenance package can
build without downloading compiler sources or the target SDK.

## Changes and review

Read [AGENTS.md](AGENTS.md) and [Conventions](Docs/Conventions.md). Add focused tests when behavior or a
failure boundary changes. Keep documentation and validation results tied to the actual code.

Use a subject such as `build(compiler): pin frontend sources`, a body explaining the reason, and a
`Signed-off-by` entry in the final trailer block. `git commit -s` adds the DCO trailer. By signing off,
you certify the
[Developer Certificate of Origin](https://developercertificate.org/).

Use small stacked changes when a feature needs several reviewable steps. Follow the pull request
template and report checks that could not run. Resolve review findings with new signed commits.
Maintainers perform merges and release publication.
