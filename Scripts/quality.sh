#!/usr/bin/env bash

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
mkdir -p .cache
swiftformat --config .swiftformat --lint . --cache .cache/swiftformat.cache
swiftlint lint --strict --quiet
shellcheck Scripts/*.sh Scripts/Hooks/*
shfmt -d -i 4 -ci Scripts/*.sh Scripts/Hooks/*
