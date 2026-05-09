# 0003: iOS XCTest Shim

## Status

Accepted.

## Context

`xcrun simctl` is good for simulator lifecycle, screenshots, logs, deep links,
and app install/launch, but it is not enough for robust selector-driven UI
automation. `xcrun devicectl` provides physical-device lifecycle operations,
but it still does not provide the selector-grade UI semantics ZMR needs. ZMR
needs iOS behavior that matches Android scenario semantics where the platforms
overlap.

## Decision

iOS support uses three layers:

- `xcrun simctl` for lifecycle, install, launch, stop, open link, clear state,
  screenshots, logs, and device discovery.
- `xcrun devicectl` for physical-device discovery, install, launch, deep-link
  launch, clear-state uninstall, and best-effort stop.
- An app-local XCTest/XCUIAutomation shim for hierarchy snapshots, element
  queries, tap, type, erase text, keyboard control, swipe, and app state on
  simulators and physical devices.

V1 iOS clear-state semantics are best-effort app uninstall by bundle id.
Physical-device screenshot and log capture remain limited until the shim grows
an explicit capture channel.

## Consequences

- iOS selector actions use platform automation APIs instead of coordinate-only
  shelling.
- App repositories must wire a UI test target when they need selector-grade iOS
  runs.
- The internal shim protocol can evolve during the dev preview, while public
  behavior remains the ZMR CLI, scenario format, JSON-RPC methods, and schemas.
- Physical iOS support depends on local signing, provisioning, Developer Mode,
  pairing, and `devicectl` transport state.
