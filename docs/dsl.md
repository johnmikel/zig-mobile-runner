# Scenario DSL

ZMR uses JSON as the V1 scenario DSL:

```json
{
  "name": "Login smoke",
  "appId": "com.example.mobiletest",
  "steps": [
    { "action": "launch" },
    { "action": "tap", "selector": { "resourceId": "email" } },
    { "action": "typeText", "text": "user@example.com" },
    { "action": "assertVisible", "selector": { "text": "Welcome" } }
  ]
}
```

## Why JSON For V1

JSON is strict, deterministic, schema-validatable, and easy for agents to emit.

- It is strict and deterministic.
- It has mature schema validation.
- It is easy for AI agents and code generators to emit.
- It works cleanly across TypeScript, Python, Go, Rust, Zig, and CI tooling.
- It avoids hidden parser behavior while the protocol is still a developer
  preview.

JSON is not the most pleasant hand-authored format for every team. That is why
ZMR keeps scenario files small, supports generated scenarios, and includes an
import path for a documented subset of mobile-flow YAML.

## Authoring Recommendation

- Use JSON for committed `.zmr/*.json` scenarios.
- Use `zmr validate --json` before device runs.
- Generate JSON from higher-level tools when humans want a friendlier surface.
- Keep selectors stable and explicit: resource ids or accessibility identifiers
  first, labels/content descriptions second, text third.

## Human-Friendly Layer

JSON should stay the canonical machine contract. A friendlier authoring layer
can come later as a compiler to JSON, not as a second runtime format.

## Roadmap

The likely production shape is:

1. JSON remains the canonical machine contract.
2. A friendlier authoring layer can compile to JSON.
3. The compiler must preserve source locations so validation errors still point
   to the human-authored file.
4. The JSON Schema and protocol fixtures remain the compatibility boundary.

This keeps agents accurate while leaving room for nicer hand-authored test
files later.
