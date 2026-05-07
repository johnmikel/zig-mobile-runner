#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

output="$("$ROOT/scripts/release-gate.sh" --dry-run 2>&1)"

python3 - "$output" <<'PY'
import sys

output = sys.argv[1]

required = [
    "zig fmt --check build.zig src",
    "bash -n scripts/*.sh tests/*.sh",
    "python3 -m py_compile scripts/*.py",
    "bash tests/benchmark-results-test.sh",
    "bash tests/device-matrix-test.sh",
    "bash tests/android-emulator-script-test.sh",
    "bash tests/android-shim-install-script-test.sh",
    "bash tests/android-pilot-script-test.sh",
    "bash tests/pilot-gate-script-test.sh",
    "bash tests/ios-demo-app-script-test.sh",
    "bash tests/ios-real-demo-script-test.sh",
    "bash tests/ios-shim-install-script-test.sh",
    "bash tests/ios-shim-target-helper-test.sh",
    "bash tests/ios-pilot-script-test.sh",
    "bash tests/ci-gate-script-test.sh",
    "bash tests/release-metadata-test.sh",
    "bash tests/release-manifest-test.sh",
    "bash tests/release-integrity-test.sh",
    "bash tests/macos-signing-script-test.sh",
    "bash tests/macos-notarization-script-test.sh",
    "bash tests/homebrew-formula-test.sh",
    "bash tests/docs-readiness-test.sh",
    "bash tests/workflow-readiness-test.sh",
    "bash tests/demo-script-test.sh",
    "node --test tests/npm-package.test.mjs",
    "bash tests/go-client-test.sh",
    "bash tests/rust-client-test.sh",
    "bash tests/public-safety-test.sh",
    "node --test tests/viewer-parser.test.mjs",
    "zig test src/main.zig -target aarch64-macos.15.0",
    "zig build-exe src/main.zig -target aarch64-macos.15.0 -O Debug -femit-bin=zig-out/bin/zmr",
    "bash tests/version-json-test.sh",
    "bash tests/schemas-json-test.sh",
    "bash tests/devices-json-test.sh",
    "bash tests/cli-error-test.sh",
    "bash tests/validate-json-test.sh",
    "bash tests/explain-json-test.sh",
    "bash tests/run-json-test.sh",
    "bash tests/init-app-test.sh",
    "bash tests/import-flow-yaml-test.sh",
    "bash tests/doctor-config-test.sh",
    "bash tests/doctor-strict-test.sh",
    "./zig-out/bin/zmr validate examples/android-app-auth-probe.json",
    "./zig-out/bin/zmr validate examples/ios-smoke.json",
    "./zig-out/bin/zmr doctor --strict --adb ./tests/fake-adb.sh --xcrun ./tests/fake-xcrun.sh",
    "./scripts/demo.sh",
    "./scripts/coverage.sh",
    "./scripts/build-release.sh",
    "./scripts/verify-release-artifacts.sh",
    "./scripts/release-smoke.sh dist/*.tar.gz",
    "npm pack --dry-run",
]

for command in required:
    assert command in output, command

assert "External pilot gates not run by default" in output
assert "./scripts/pilot-gate.sh --android --ios --android-app-root /path/to/mobile-app --ios-app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app --ios-shim /path/to/mobile-app/.zmr/ios-shim" in output
assert "./scripts/run-android-pilot.sh --app-root /path/to/mobile-app --device emulator-5554 --runs 20" in output
assert "./scripts/run-android-pilot.sh --app-root /path/to/mobile-app --device emulator-5554 --runs 20 --min-pass-rate 100 --max-failures 0 --max-p95-ms 30000" in output
assert "./scripts/run-ios-pilot.sh --app-root /path/to/mobile-app --app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app --device booted --ios-shim /path/to/mobile-app/.zmr/ios-shim --runs 20" in output
assert "./scripts/run-ios-pilot.sh --app-root /path/to/mobile-app --app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app --device booted --ios-shim /path/to/mobile-app/.zmr/ios-shim --runs 20 --min-pass-rate 100 --max-failures 0 --max-p95-ms 45000" in output
PY
