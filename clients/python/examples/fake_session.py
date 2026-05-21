#!/usr/bin/env python3
import json
import os

import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from zmr_client import ZmrClient  # noqa: E402


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))


with ZmrClient(
    os.path.join(ROOT, "zig-out", "bin", "zmr"),
    [
        "serve",
        "--transport",
        "stdio",
        "--device",
        "fake-android-1",
        "--app-id",
        "com.example.mobiletest",
        "--adb",
        os.path.join(ROOT, "tests", "fake-adb.sh"),
        "--trace-dir",
        "traces/demo-python-client",
    ],
) as zmr:
    capabilities = zmr.capabilities()
    zmr.create_session()
    zmr.open_link("exampleapp://e2e-auth?probe=1")
    zmr.assert_healthy(timeout_ms=100)
    snapshot = zmr.snapshot()
    events = zmr.trace_events(0, limit=20)
    zmr.export_trace("traces/demo-python-client-redacted.zmrtrace", redact=True, omit_screenshots=True)
    print(
        json.dumps(
            {
                "protocolVersion": capabilities["protocolVersion"],
                "activePackage": snapshot["activePackage"],
                "nodes": len(snapshot["nodes"]),
                "events": len(events["events"]),
            },
            separators=(",", ":"),
        )
    )
