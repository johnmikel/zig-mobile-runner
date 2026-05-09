# Market Positioning

ZMR is a developer-preview runner. It should compete by being the best local
mobile automation control plane for AI agents, not by pretending to be a mature
drop-in replacement for every existing runner on day one.

## What The Market Rewards

Detox positions itself as a React Native E2E framework with gray-box
synchronization, JavaScript tests, and CI workflows. Its docs emphasize that
gray-box access helps reduce flakiness by observing app internals, and its
README shows tests written with `element(by.id(...))` and Jest-style
assertions.

Maestro positions itself around simple YAML flows, quick setup, visual tooling,
cloud, and broad platform support. Its public docs call Maestro a YAML-based
mobile and web UI automation framework. The `maestro-runner` project positions
itself as a single-binary alternative that runs existing YAML flows and claims
Android, iOS, web, cloud, reports, JavaScript scripting, and parallel execution.

Lightpanda is a fast Zig browser runtime with CDP and MCP surfaces. It is a
useful architectural reference for a small native automation engine, but it is
web-first. ZMR should not clone browser automation. Its opportunity is a
mobile-native equivalent: device lifecycle, app install/launch/clear state,
accessibility trees, selector actions, logs, screenshots, trace bundles, and
physical-device workflows.

## ZMR Position

ZMR should lead with:

- **Agent-native protocol:** structured snapshots and actions over JSON-RPC,
  plus an MCP stdio server for agent runtimes.
- **Semantic mobile tree:** normalized roles, names, selectors, bounds, and
  recommended actions so agents do not parse platform-specific hierarchy dumps.
- **Trace-first reliability:** every action produces evidence agents and humans
  can inspect.
- **Small deterministic core:** Zig runner, explicit adapters, schema-validated
  inputs, stable CLI JSON.
- **App-local setup:** `.zmr/` owns config, scenarios, shims, and private traces.
- **Language-neutral clients:** TypeScript, Python, Go, and Rust can all drive
  the same protocol.

## Where ZMR Is Already Strong

| Area | ZMR advantage |
| --- | --- |
| AI agent integration | First-class JSON-RPC, MCP tools, semantic snapshots, live trace events, schemas, agent guide, packaged skill |
| Failure diagnostics | Trace bundles, snapshot replay, UI tree, screenshots, logs, `zmr explain` |
| Language neutrality | Protocol clients across multiple languages |
| Local release discipline | Release gate, coverage gate, artifacts, SBOM, checksums, attestation |
| App-local privacy | `.zmr/` config and redacted trace export |
| Mobile focus versus browser engines | Native Android/iOS device lifecycle and accessibility semantics instead of CDP-only web primitives |

## Where ZMR Must Catch Up

| Area | Gap |
| --- | --- |
| npm distribution | Tarball exists in GitHub release, registry publish still pending |
| Android proof | Needs repeated public generic Android demo and app-local pilots |
| iOS scale | Simulator demo passes, but repeated-run evidence should be published |
| Physical iOS | Initial local support exists through `devicectl` plus the XCTest shim; screenshot/log capture still needs hardening |
| Cloud | Not supported yet |
| Human DSL | JSON is reliable for agents; a friendlier authoring layer should compile to JSON |
| Brand surface | README is now concise; a docs/landing site should follow after npm publish |

## Website Recommendation

For `0.1.x`, GitHub README plus release assets are enough. After npm publish,
create a docs site with:

- homepage: value proposition, install, demo GIF/video, trace viewer screenshot
- docs: install, `.zmr/`, scenarios, JSON-RPC, clients, shims, privacy
- compare: honest capability matrix
- examples: Android app, iOS app, agent session
- releases: checksums, SBOM, artifact verification

Do not create a marketing-only site before the npm package and repeated device
evidence are in place. The strongest market fit is a clean first-run path that
actually works.

## Sources

- Detox GitHub repository: https://github.com/wix/Detox
- Detox getting started docs: https://wix.github.io/Detox/docs/introduction/getting-started/
- Maestro docs: https://docs.maestro.dev/
- maestro-runner GitHub repository: https://github.com/devicelab-dev/maestro-runner
- Lightpanda browser repository: https://github.com/lightpanda-io/browser
