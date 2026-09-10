#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
history_fixture="$(mktemp -d "${TMPDIR:-/tmp}/toolchain-history.XXXXXX")"
trap 'rm -rf "$history_fixture"' EXIT

git -C "$history_fixture" init --quiet --initial-branch=main
git -C "$history_fixture" fast-import --quiet <Tests/Fixtures/CommitHistory.fastimport

Scripts/check-history.sh "$history_fixture" main feature
Scripts/check-history.sh "$history_fixture" main merge-only

printf '%s\n' 'Error: Add your Signed-off-by name and email to the final trailer block.' >"$history_fixture/missing-signoff"
printf '%s\n' 'Error: Use a scoped Conventional Commit subject under 72 characters.' >"$history_fixture/invalid-subject"

history_result=0
Scripts/check-history.sh "$history_fixture" main unsigned >"$history_fixture/result" 2>&1 || history_result=$?
test "$history_result" -eq 1
cmp "$history_fixture/missing-signoff" "$history_fixture/result"

history_result=0
Scripts/check-history.sh "$history_fixture" main message-merge >"$history_fixture/result" 2>&1 || history_result=$?
test "$history_result" -eq 1
cmp "$history_fixture/invalid-subject" "$history_fixture/result"

history_result=0
Scripts/check-history.sh "$history_fixture" main empty-message >"$history_fixture/result" 2>&1 || history_result=$?
test "$history_result" -eq 1
cmp "$history_fixture/invalid-subject" "$history_fixture/result"

history_result=0
Scripts/check-history.sh "$history_fixture" main merged-side >"$history_fixture/result" 2>&1 || history_result=$?
test "$history_result" -eq 1
cmp "$history_fixture/missing-signoff" "$history_fixture/result"

history_result=0
Scripts/check-history.sh "$history_fixture" missing-revision feature >"$history_fixture/result" 2>&1 || history_result=$?
test "$history_result" -eq 128

printf '%s\n' 'Validated Git history selection and commit-policy failures.'
