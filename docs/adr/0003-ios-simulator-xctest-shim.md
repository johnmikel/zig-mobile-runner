# 0003: iOS Simulator XCTest Shim

## Status

Accepted.

## Context

`xcrun simctl` is good for simulator lifecycle, screenshots, logs, deep links,
and app install/launch, but it is not enough for robust selector-driven UI
automation. ZMR needs iOS behavior that matches Android scenario semantics where
the platforms overlap.

## Decision

iOS simulator support uses two layers:

- `xcrun simctl` for lifecycle, install, launch, stop, open link, clear state,
  screenshots, logs, and device discovery.
- An app-local XCTest/XCUIAutomation shim for hierarchy snapshots, element
  queries, tap, type, erase text, keyboard control, swipe, and app state.

Physical iOS devices are out of the current support matrix. V1 iOS clear-state
semantics are best-effort simulator app uninstall by bundle id.

## Consequences

- iOS selector actions use platform automation APIs instead of coordinate-only
  shelling.
- App repositories must wire a simulator UI test target when they need
  selector-grade iOS runs.
- The internal shim protocol can evolve during the dev preview, while public
  behavior remains the ZMR CLI, scenario format, JSON-RPC methods, and schemas.
- Physical device support needs a separate decision because signing,
  provisioning, and transport constraints are different from simulator runs.
