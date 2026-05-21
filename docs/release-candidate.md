# Release Candidate Gate

`scripts/release-candidate.sh` is the evidence-producing gate for deciding
whether a build is ready to publish as a dev-preview release candidate. It
wraps the existing release checks, adds public Android/iOS demo evidence, and
can optionally require private app/device pilots.

## Local Mode

Run this before opening or tagging a release candidate when no devices are
attached:

```bash
./scripts/release-candidate.sh --mode local
```

Local mode runs `./scripts/release-gate.sh`, builds the generated public
Android demo APK, and runs the generated public iOS simulator demo five times
by default. If an Android AVD is available, pass `--local-android-avd <name>`
to run the generated Android demo app on an emulator instead of only building
it:

```bash
./scripts/release-candidate.sh --mode local \
  --local-android-avd Small_Phone \
  --local-android-demo-runs 5
```

Use `--local-android-device <serial>` when the emulator serial is not
`emulator-5554`. Override the iOS demo loop with `--local-ios-demo-runs <n>`
when collecting slower or faster release-candidate evidence. It writes:

- `evidence.jsonl`: one row per gate step with command, status, mode,
  duration, structured app/device provenance, and structured threshold fields
  for hardware pilot rows.
- `summary.md`: a human-readable checklist suitable for release notes or PR
  review, including the matching `zmr-release-readiness` command and its
  blocked requirement output.

Turn that evidence into an explicit release decision:

```bash
zmr-release-readiness --evidence traces/release-candidate/<run>/evidence.jsonl \
  --target dev-preview
```

For production or market-claim checks, keep private app pilot evidence in the
app repository and pass it as a second evidence file:

```bash
zmr-release-readiness \
  --evidence traces/release-candidate/<run>/evidence.jsonl \
  --evidence /path/to/app/traces/zmr-pilots/evidence.jsonl \
  --target production \
  --json
```

`dev-preview` requires the local release gate plus public Android and iOS demo
evidence. `production` additionally requires repeated real app Android, iOS
simulator, and physical iOS pilots. `market-claim` additionally requires a
same-host/device benchmark comparison before claiming leadership over other
mobile E2E runners.

## Hardware Mode

Run this before claiming real app/device reliability:

```bash
./scripts/release-candidate.sh --mode hardware \
  --android-app-root /path/to/mobile-app \
  --android-app-id com.example.mobiletest \
  --android-device emulator-5554 \
  --ios-app-root /path/to/mobile-app \
  --ios-app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app \
  --ios-app-id com.example.mobiletest \
  --ios-device booted \
  --ios-shim /path/to/mobile-app/.zmr/ios-shim \
  --xcrun xcrun \
  --ios-physical-app-root /path/to/mobile-app \
  --ios-physical-app-path /path/to/mobile-app/build/Release-iphoneos/Sample.ipa \
  --ios-physical-app-id com.example.mobiletest \
  --ios-physical-device <physical-device-id> \
  --ios-physical-shim /path/to/mobile-app/.zmr/ios-shim
```

Hardware mode delegates evidence collection through `scripts/pilot-gate.sh`.
The Android+iOS simulator gate writes the Android and simulator rows, and the
physical iOS gate writes both `physical iOS readiness` and `iOS physical
hardware pilot` rows. If hardware mode is run with a custom `--xcrun` path, the
release-candidate gate forwards that path to the physical-readiness check as
well as the iOS pilots. Use the `serial` value from:

```bash
zmr devices --json --platform ios --ios-device-type physical
```

The physical iOS step must use a connected, trusted device with Developer Mode
enabled. Missing physical iOS evidence means physical iOS reliability is not
shipped.

## Full Candidate

Run both local and hardware gates:

```bash
./scripts/release-candidate.sh --mode all --runs 20
```

Use `--dry-run` to inspect the command plan and generate planned
`evidence.jsonl` / `summary.md` files without executing device or release
commands.
