#!/usr/bin/env node
import path from "node:path";
import url from "node:url";
import { createZmrClient } from "../index.mjs";

const root = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), "../../..");

const zmr = createZmrClient({
  command: path.join(root, "zig-out", "bin", "zmr"),
  args: [
    "serve",
    "--transport", "stdio",
    "--device", "fake-android-1",
    "--app-id", "com.example.mobiletest",
    "--adb", path.join(root, "tests", "fake-adb.sh"),
    "--trace-dir", "traces/demo-typescript-client",
  ],
});

try {
  const capabilities = await zmr.capabilities();
  await zmr.createSession();
  await zmr.openLink("exampleapp://e2e-auth?probe=1");
  const snapshot = await zmr.snapshot();
  const events = await zmr.traceEvents(0, { limit: 20 });
  await zmr.exportTrace("traces/demo-typescript-client-redacted.zmrtrace", { redact: true, omitScreenshots: true });
  console.log(JSON.stringify({
    protocolVersion: capabilities.protocolVersion,
    activePackage: snapshot.activePackage,
    nodes: snapshot.nodes.length,
    events: events.events.length,
  }));
} finally {
  await zmr.close();
}
