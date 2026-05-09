#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_file() {
  test -f "$ROOT/$1"
}

require_grep() {
  local needle="$1"
  local file="$2"
  if ! grep -q "$needle" "$ROOT/$file"; then
    echo "missing '$needle' in $file" >&2
    exit 1
  fi
}

require_file README.md
require_file FEATURES.md
require_file SECURITY.md
require_file CONTRIBUTING.md
require_file CHANGELOG.md
require_file clients/README.md
require_file docs/install.md
require_file docs/config.md
require_file docs/protocol.md
require_file docs/demo.md
require_file docs/npm.md
require_file docs/benchmarking.md
require_file docs/troubleshooting.md
require_file docs/publication.md
require_file docs/shipping.md
require_file docs/trace-privacy.md
require_file docs/ai-agents.md
require_file docs/clients.md
require_file docs/client-installation.md
require_file docs/dsl.md
require_file docs/market-positioning.md
require_file docs/adr/README.md
require_file schemas/README.md
require_file clients/python/pyproject.toml
require_file clients/swift/Package.swift
require_file clients/swift/Sources/ZMRClient/ZMRClient.swift
require_file clients/kotlin/build.gradle.kts
require_file clients/kotlin/src/main/kotlin/dev/zmr/ZmrClient.kt
require_file skills/zmr-mobile-testing/SKILL.md

require_file .github/ISSUE_TEMPLATE/bug_report.yml
require_file .github/ISSUE_TEMPLATE/feature_request.yml
require_file .github/ISSUE_TEMPLATE/config.yml

require_grep '^# Zig Mobile Runner$' README.md
require_grep 'Agent-native mobile UI automation' README.md
require_grep 'registry package is pending publish' README.md
require_grep 'npm install --save-dev https://github.com/johnmikel/zig-mobile-runner/releases/download/v0.1.0-dev.1' README.md
require_grep '## Scenario Example' README.md
require_grep 'JSON is strict' README.md
require_grep '## Agent And Language Clients' README.md
require_grep 'Rust uses `src/lib.rs`' README.md
require_grep 'physical iOS devices use `devicectl`' README.md
require_grep 'iOS physical device' README.md
require_grep 'zmr validate --json' README.md
require_grep 'zmr devices --json' README.md
require_grep 'zmr schemas --json' README.md
require_grep 'zmr import flow-yaml' README.md
require_grep 'verify-release-artifacts.sh' README.md
require_grep 'RELEASE_MANIFEST.json' README.md
require_grep 'release-manifest.schema.json' README.md
require_grep 'schemas-output.schema.json' README.md
require_grep 'version-output.schema.json' README.md
require_grep 'capabilities-output.schema.json' README.md
require_grep 'semantic-snapshot.schema.json' README.md
require_grep 'init-output.schema.json' README.md
require_grep 'devices-output.schema.json' README.md
require_grep 'validate-output.schema.json' README.md
require_grep 'run-output.schema.json' README.md
require_grep 'explain-output.schema.json' README.md
require_grep 'docs/adr/' README.md
require_grep 'docs/ai-agents.md' README.md
require_grep 'docs/clients.md' README.md
require_grep 'docs/client-installation.md' README.md
require_grep 'docs/dsl.md' README.md
require_grep 'docs/market-positioning.md' README.md
require_grep 'skills/zmr-mobile-testing/SKILL.md' README.md

require_grep 'Agent Interface' FEATURES.md
require_grep 'MCP stdio server' FEATURES.md
require_grep 'Current Limitations' FEATURES.md
require_grep 'Physical iOS devices through `xcrun devicectl`' FEATURES.md
require_grep 'Physical iOS devices are supported for local lifecycle' CHANGELOG.md
require_grep 'Architecture decision records' CHANGELOG.md
require_grep 'AI agent integration guide' CHANGELOG.md
require_grep 'zmr-benchmark-command' CHANGELOG.md
require_grep 'zmr-compare-benchmarks' CHANGELOG.md

require_grep 'JSON is strict' docs/dsl.md
require_grep 'Human-Friendly Layer' docs/dsl.md
require_grep 'Rust has `src/lib.rs`' docs/clients.md
require_grep 'TypeScript' clients/README.md
require_grep 'Python' clients/README.md
require_grep 'Go' clients/README.md
require_grep 'Rust' clients/README.md
require_grep 'Swift' clients/README.md
require_grep 'Kotlin' clients/README.md
require_grep 'Homebrew' docs/client-installation.md
require_grep 'pip install' docs/client-installation.md
require_grep 'go get' docs/client-installation.md
require_grep 'zmr-client' docs/client-installation.md
require_grep 'Market Positioning' docs/market-positioning.md
require_grep 'Detox' docs/market-positioning.md
require_grep 'Maestro' docs/market-positioning.md
require_grep 'GitHub README plus release assets' docs/market-positioning.md

require_grep 'Architecture Decisions' docs/adr/README.md
require_grep 'Agent-Native Runner Boundary' docs/adr/0001-agent-native-runner-boundary.md
require_grep 'App-Local `.zmr/` Contract' docs/adr/0002-app-local-zmr-contract.md
require_grep 'iOS XCTest Shim' docs/adr/0003-ios-simulator-xctest-shim.md
require_grep 'Benchmark Claims And Baseline Collection' docs/adr/0004-benchmark-claims-and-baseline-collection.md

require_grep 'AI Agent Guide' docs/ai-agents.md
require_grep 'runner.capabilities' docs/ai-agents.md
require_grep 'zmr mcp' docs/ai-agents.md
require_grep 'semantic_snapshot' docs/ai-agents.md
require_grep 'trace.export' docs/ai-agents.md
require_grep 'zmr-mobile-testing' skills/zmr-mobile-testing/SKILL.md

require_grep 'zmr init --app' docs/install.md
require_grep 'zmr init --app' docs/config.md
require_grep 'zmr init --app' docs/demo.md
require_grep 'zmr init --app' docs/npm.md
require_grep 'zmr init --json' docs/protocol.md
require_grep 'Relative scenario, trace, and shim paths from config resolve against the app' docs/config.md
require_grep 'zmr version --json' docs/protocol.md
require_grep 'zmr mcp' docs/protocol.md
require_grep 'observe.semanticSnapshot' docs/protocol.md
require_grep 'zmr schemas --json' docs/protocol.md
require_grep 'zmr devices --json' docs/protocol.md
require_grep 'zmr validate <scenario.json> --json' docs/protocol.md
require_grep 'zmr explain' docs/troubleshooting.md
require_grep 'pilot wrappers run setup preflights' docs/troubleshooting.md

require_grep 'zmr-device-matrix' docs/benchmarking.md
require_grep 'zmr-benchmark-command' docs/benchmarking.md
require_grep 'zmr-compare-benchmarks' docs/benchmarking.md
require_grep 'zmr-pilot-gate' docs/benchmarking.md
require_grep 'matrix.jsonl' docs/benchmarking.md
require_grep 'summary.json' docs/benchmarking.md

require_grep 'verify-release-artifacts.sh' docs/install.md
require_grep 'verify-release-artifacts.sh' docs/shipping.md
require_grep 'RELEASE_MANIFEST.json' docs/install.md
require_grep 'RELEASE_MANIFEST.json' docs/shipping.md
require_grep 'artifact attestation' docs/shipping.md
require_grep 'release-manifest.schema.json' docs/protocol.md
require_grep 'sign-macos-release.sh' docs/install.md
require_grep 'notarize-macos-release.sh' docs/install.md
require_grep 'npm publish' docs/install.md
require_grep 'npm publish' docs/shipping.md
require_grep 'provenance' docs/shipping.md
require_grep 'Public GitHub Publication' docs/publication.md
require_grep './scripts/release-gate.sh' docs/publication.md
require_grep 'tests/public-safety-test.sh' docs/publication.md
require_grep 'Do not commit generated traces' docs/publication.md

require_grep 'schemas-output.schema.json' schemas/README.md
require_grep 'version-output.schema.json' schemas/README.md
require_grep 'capabilities-output.schema.json' schemas/README.md
require_grep 'semantic-snapshot.schema.json' schemas/README.md
require_grep 'init-output.schema.json' schemas/README.md
require_grep 'import-output.schema.json' schemas/README.md
require_grep 'devices-output.schema.json' schemas/README.md
require_grep 'validate-output.schema.json' schemas/README.md
require_grep '"schemas"' schemas/schemas-output.schema.json
require_grep '"protocolVersion"' schemas/version-output.schema.json
require_grep '"platformSupport"' schemas/capabilities-output.schema.json
require_grep '"physicalDevices"' schemas/capabilities-output.schema.json
require_grep '"recommendedAction"' schemas/semantic-snapshot.schema.json
require_grep '"mode"' schemas/init-output.schema.json
require_grep '"format"' schemas/import-output.schema.json
require_grep '"platform"' schemas/devices-output.schema.json
require_grep '"stepCount"' schemas/validate-output.schema.json
require_grep '"failedStepIndex"' schemas/run-output.schema.json
require_grep '"diagnostic"' schemas/explain-output.schema.json

if grep -q 'iOS simulator support is a preview' "$ROOT/README.md" "$ROOT/docs/install.md" "$ROOT/docs/shipping.md" "$ROOT/docs/protocol.md"; then
  echo "iOS simulator support should not be documented as preview" >&2
  exit 1
fi

if grep -q 'iOS simulator support remains preview' "$ROOT/CHANGELOG.md"; then
  echo "changelog still lists iOS simulator support as preview" >&2
  exit 1
fi
