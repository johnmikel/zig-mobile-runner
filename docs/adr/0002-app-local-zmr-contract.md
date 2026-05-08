# 0002: App-Local `.zmr/` Contract

## Status

Accepted.

## Context

Mobile app repositories need a predictable place for runner configuration,
smoke scenarios, shim commands, and setup scripts. ZMR should be installable as
an npm dev dependency, but it should also work from source checkouts and
release archives.

## Decision

`.zmr/` is the app-local contract. The default config file is
`.zmr/config.json`, validated by `schemas/config.schema.json`. ZMR commands
auto-discover the config from the app checkout, and explicit CLI flags always
override config defaults.

`zmr-wizard` and `zmr init --app` scaffold the same shape:

- `.zmr/config.json`
- `.zmr/android-smoke.json`
- `.zmr/ios-smoke.json`
- optional shim commands and source files
- app package script suggestions
- `traces/` ignored by default

## Consequences

- App-specific scenarios and private traces stay in the app repository, not in
  the public ZMR repo.
- npm, source, and release-archive installs share one integration model.
- Agents can discover the same setup state humans use through `zmr doctor`,
  `zmr schemas`, and `.zmr/config.json`.
- Generated files need backwards-compatible schema handling and clear
  diagnostics because app repositories may pin older versions.
