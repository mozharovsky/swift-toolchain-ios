#!/usr/bin/env bash

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
Scripts/quality.sh
swift build
swift test
Scripts/check-history-fixtures.sh
swift run --skip-build toolchain verify
git ls-files --cached --others --exclude-standard -z | swift run --skip-build toolchain check-repository
Scripts/docs.sh
Scripts/native-check.sh
