# ZMR Android Shim

This directory contains the native Android instrumentation shim scaffold that
supplements the current ADB/UI Automator adapter.

Current status:

- `src/android.zig` provides the production preview path through ADB, shell
  input, screenshots, logcat, and UI Automator XML.
- `src/android.zig` can run a configured shim command with one JSON request on
  stdin and one JSON response on stdout.
- `scripts/install-android-shim.sh` writes an app-local `.zmr/android-shim`
  command and copies the instrumentation source file into the app repo for
  inclusion in `androidTest`.

V1 target:

- Faster hierarchy retrieval than repeated shell UI Automator dumps.
- Reliable tap, type, swipe, and key actions with ADB fallback.
- App idle/settle signals where Android APIs expose them reliably.
- Clean error envelopes that flow into existing ZMR traces.
