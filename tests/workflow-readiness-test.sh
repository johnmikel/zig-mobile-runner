#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI="$ROOT/.github/workflows/ci.yml"
RELEASE="$ROOT/.github/workflows/release.yml"

test -f "$CI"
test -f "$RELEASE"

grep -q 'brew install zig kcov' "$CI"
grep -q 'gem install xcodeproj' "$CI"
grep -q './scripts/release-gate.sh' "$CI"

grep -q 'brew install zig kcov' "$RELEASE"
grep -q 'gem install xcodeproj' "$RELEASE"
grep -q 'ZMR_VERSION="${GITHUB_REF_NAME#v}"' "$RELEASE"
grep -q './scripts/release-gate.sh' "$RELEASE"
grep -q 'attestations: write' "$RELEASE"
grep -q 'id-token: write' "$RELEASE"
grep -q 'actions/attest-build-provenance@v2' "$RELEASE"
grep -q 'softprops/action-gh-release@v2' "$RELEASE"
grep -q 'dist/RELEASE_MANIFEST.json' "$RELEASE"
grep -q 'actions/setup-node@v4' "$RELEASE"
grep -q 'npm version --no-git-tag-version "${GITHUB_REF_NAME#v}"' "$RELEASE"
grep -q 'npm run pack:npm' "$RELEASE"
grep -q 'dist/zig-mobile-runner-\*.tgz' "$RELEASE"
grep -q 'NODE_AUTH_TOKEN' "$RELEASE"
grep -q 'npm publish dist/zig-mobile-runner-\*.tgz --provenance --access public' "$RELEASE"
