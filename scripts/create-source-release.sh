#!/usr/bin/env bash
# Create a source-only GitHub Release from a clean main checkout.
# Usage: bash scripts/create-source-release.sh YK-v1.0.0-alpha.1
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

tag="${1:-}"
pattern='^YK-v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$'

if [[ -z "$tag" ]]; then
  printf 'Usage: %s YK-v1.0.0-alpha.1\n' "$0" >&2
  exit 1
fi

if [[ ! "$tag" =~ $pattern ]]; then
  printf 'STOP: tag %s does not match %s\n' "$tag" "$pattern" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  printf 'STOP: working tree is not clean.\n' >&2
  git status --short >&2
  exit 1
fi

branch="$(git branch --show-current)"
if [[ "$branch" != "main" ]]; then
  printf 'STOP: checkout main before releasing (current: %s).\n' "$branch" >&2
  exit 1
fi

git fetch origin main
if ! git merge-base --is-ancestor origin/main HEAD; then
  printf 'STOP: local main does not contain origin/main.\n' >&2
  exit 1
fi
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  printf 'STOP: local main and origin/main differ. Push or pull first.\n' >&2
  exit 1
fi

notes="docs/releases/${tag}.md"
if [[ ! -f "$notes" ]]; then
  printf 'STOP: missing %s\n' "$notes" >&2
  exit 1
fi

if [[ "$(head -n 1 "$notes")" == \#* ]]; then
  printf 'STOP: %s starts with a markdown heading. GitHub already shows the release title; start the notes with body text.\n' "$notes" >&2
  exit 1
fi

if ! grep -q "$tag" CHANGELOG.md; then
  printf 'STOP: CHANGELOG.md does not mention %s\n' "$tag" >&2
  exit 1
fi

if git rev-parse --verify "refs/tags/${tag}" >/dev/null 2>&1; then
  printf 'STOP: tag %s already exists locally.\n' "$tag" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
  printf 'STOP: tag %s already exists on origin.\n' "$tag" >&2
  exit 1
fi

prerelease_args=()
if [[ "$tag" == *alpha* || "$tag" == *beta* || "$tag" == *rc* ]]; then
  prerelease_args+=(--prerelease)
fi

git tag -a "$tag" -m "$tag"
git push origin "refs/tags/${tag}"

if gh release view "$tag" >/dev/null 2>&1; then
  printf 'Release %s already exists (tag workflow may have created it).\n' "$tag"
else
  gh release create "$tag" \
    --title "${tag}" \
    --notes-file "$notes" \
    --verify-tag \
    "${prerelease_args[@]}"
fi

printf 'Created source-only GitHub Release %s\n' "$tag"
printf 'Confirm the Release page has no ipa/xcarchive attachments.\n'
