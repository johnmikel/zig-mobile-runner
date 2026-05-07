#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"

usage() {
  cat <<'USAGE'
Usage:
  scripts/verify-release-artifacts.sh [--dist <dir>]

Verifies release archive checksums and required metadata files.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dist)
      DIST="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$DIST" ]]; then
  echo "dist directory not found: $DIST" >&2
  exit 2
fi

CHECKSUMS="$DIST/SHA256SUMS"
if [[ ! -s "$CHECKSUMS" ]]; then
  echo "missing SHA256SUMS: $CHECKSUMS" >&2
  exit 1
fi

required_files=(
  "SBOM.spdx.json"
  "THIRD_PARTY_NOTICES.md"
  "homebrew/zmr.rb"
  "RELEASE_MANIFEST.json"
)

archives=()
while IFS= read -r archive; do
  archives+=("$(basename "$archive")")
done < <(find "$DIST" -maxdepth 1 -type f -name '*.tar.gz' | sort)
npm_packages=()
while IFS= read -r package; do
  npm_packages+=("$(basename "$package")")
done < <(find "$DIST" -maxdepth 1 -type f -name '*.tgz' | sort)

if [[ "${#archives[@]}" -eq 0 ]]; then
  echo "no release archives found in $DIST" >&2
  exit 1
fi

has_checksum_entry() {
  local path="$1"
  awk '{ print $2 }' "$CHECKSUMS" | sed 's#^\./##' | grep -Fxq "$path"
}

for archive in "${archives[@]}"; do
  required_files+=("$archive")
done
if [[ "${#npm_packages[@]}" -gt 0 ]]; then
  for package in "${npm_packages[@]}"; do
    required_files+=("$package")
  done
fi

for path in "${required_files[@]}"; do
  if [[ ! -f "$DIST/$path" ]]; then
    echo "missing release artifact: $path" >&2
    exit 1
  fi
  if ! has_checksum_entry "$path"; then
    echo "missing checksum entry: $path" >&2
    exit 1
  fi
done

while read -r expected path; do
  path="${path#./}"
  if [[ -z "$expected" || -z "$path" ]]; then
    continue
  fi
  if [[ "$path" = /* || "$path" == *".."* ]]; then
    echo "unsafe checksum path: $path" >&2
    exit 1
  fi
  if [[ ! -f "$DIST/$path" ]]; then
    echo "checksum references missing file: $path" >&2
    exit 1
  fi
  actual="$(shasum -a 256 "$DIST/$path" | awk '{ print $1 }')"
  if [[ "$actual" != "$expected" ]]; then
    echo "checksum mismatch: $path" >&2
    exit 1
  fi
done < "$CHECKSUMS"

node - "$DIST" <<'NODE'
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const dist = process.argv[2];
const manifestPath = path.join(dist, "RELEASE_MANIFEST.json");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

if (manifest.schemaVersion !== 1) {
  throw new Error("release manifest schemaVersion must be 1");
}
if (!Array.isArray(manifest.artifacts)) {
  throw new Error("release manifest artifacts must be an array");
}

const artifactByPath = new Map();
for (const artifact of manifest.artifacts) {
  if (!artifact || typeof artifact.path !== "string") {
    throw new Error("release manifest artifact path missing");
  }
  if (path.isAbsolute(artifact.path) || artifact.path.includes("..")) {
    throw new Error(`release manifest unsafe path: ${artifact.path}`);
  }
  artifactByPath.set(artifact.path, artifact);

  const filePath = path.join(dist, artifact.path);
  const bytes = fs.readFileSync(filePath);
  const sha256 = crypto.createHash("sha256").update(bytes).digest("hex");
  if (artifact.sha256 !== sha256) {
    throw new Error(`release manifest checksum mismatch: ${artifact.path}`);
  }
  if (artifact.sizeBytes !== bytes.length) {
    throw new Error(`release manifest size mismatch: ${artifact.path}`);
  }
}

const required = fs.readdirSync(dist)
  .filter((name) => name.endsWith(".tar.gz"))
  .sort();
for (const name of fs.readdirSync(dist).filter((entry) => entry.endsWith(".tgz")).sort()) {
  required.push(name);
}
required.push("SBOM.spdx.json", "THIRD_PARTY_NOTICES.md", "homebrew/zmr.rb");

for (const relativePath of required) {
  const artifact = artifactByPath.get(relativePath);
  if (!artifact) throw new Error(`release manifest missing artifact: ${relativePath}`);
}
NODE

printf 'verified release artifacts: archives=%d dist=%s\n' "${#archives[@]}" "$DIST"
