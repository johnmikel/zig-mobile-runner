# ZMR Release Notes Template

## Version

`vX.Y.Z`

## Release Type

- Dev preview
- Alpha
- Beta
- Stable

## Highlights

- ...

## Platform Support

- Android:
- iOS:

## Breaking Changes

- None.

## Added

- ...

## Changed

- ...

## Fixed

- ...

## Known Limitations

- ...

## Verification

Paste the release gate output summary:

```text
zig fmt --check build.zig src
bash -n scripts/*.sh tests/*.sh
zig test src/main.zig -target aarch64-macos.15.0
./scripts/demo.sh
./scripts/coverage.sh
./scripts/build-release.sh
```

## Checksums

Paste `dist/SHA256SUMS`.
