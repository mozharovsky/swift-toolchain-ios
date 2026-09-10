#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
history_repository="${1:?Pass a Git repository directory.}"
base_revision="${2:?Pass the excluded base revision.}"
head_revision="${3:?Pass the included head revision.}"

git -C "$history_repository" log --no-merges --format=%B -z "$base_revision..$head_revision" |
    swift run --quiet --package-path "$repository_root" --skip-build toolchain check-history
