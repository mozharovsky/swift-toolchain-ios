#!/usr/bin/env bash

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
mkdir -p .cache/docc
swift package --allow-writing-to-directory .cache/docc/ToolchainSupport generate-documentation \
    --target ToolchainSupport --output-path .cache/docc/ToolchainSupport \
    --symbol-graph-minimum-access-level private --warnings-as-errors
swift package --allow-writing-to-directory .cache/docc/ToolchainCLI generate-documentation \
    --target ToolchainCLI --output-path .cache/docc/ToolchainCLI \
    --symbol-graph-minimum-access-level private --warnings-as-errors
