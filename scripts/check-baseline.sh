#!/usr/bin/env bash
# Read-only gate. Fetch origin/main immediately before running this script.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
printf 'Repository: %s\nBranch: %s\nHEAD: %s\n' "$(pwd -P)" "$(git branch --show-current)" "$(git rev-parse HEAD)"
for ref in main origin/main; do
    if ! git rev-parse --verify "$ref^{commit}" >/dev/null 2>&1; then
        printf 'STOP: missing %s; inspect and fetch the baseline first.\n' "$ref" >&2
        exit 1
    fi
    if ! git merge-base --is-ancestor "$ref" HEAD; then
        printf 'STOP: HEAD does not contain %s. Reconcile without discarding local work.\n' "$ref" >&2
        exit 1
    fi
done
printf 'Baseline ancestry OK. Uncommitted content (must be included in build provenance):\n'
git status --short
