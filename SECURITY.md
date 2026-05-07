# Security Policy

ZMR is a local mobile automation runner. It can collect screenshots, UI trees,
logs, app ids, device metadata, and scenario inputs. Treat raw traces as
sensitive.

## Supported Versions

The current supported line is `0.1.x` dev preview. Security fixes should target
the latest dev-preview branch until a stable release exists.

## Reporting A Vulnerability

Open a private security advisory on GitHub when available. If private advisory
reporting is not enabled, contact the repository maintainer through the channel
listed in the project profile.

Include:

- ZMR version and platform.
- Reproduction steps.
- Whether the issue exposes screenshots, logs, trace data, credentials, or
  device access.
- A minimal scenario or redacted trace bundle when possible.

Do not publish raw traces from private apps in public issues.

## Trace Handling

- Use `zmr export --redact` before sharing trace bundles.
- Do not share raw screenshot artifacts from private apps.
- Do not paste logs that include tokens, emails, API keys, or device identifiers.
- Prefer fake-device reproductions for public bug reports.

