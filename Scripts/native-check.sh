#!/usr/bin/env bash

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
cmake -S . -B .cache/native-check -G Ninja -DCMAKE_BUILD_TYPE=Debug \
    -DTOOLCHAIN_ENABLE_SANITIZERS=ON -DTOOLCHAIN_ENABLE_COMPILER_BUILD=OFF
cmake --build .cache/native-check --parallel 4
ctest --test-dir .cache/native-check --output-on-failure
