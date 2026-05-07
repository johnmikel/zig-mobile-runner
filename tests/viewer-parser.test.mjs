import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { test } from "node:test";

const require = createRequire(import.meta.url);
const {
  buildTraceModel,
  parseEventsJsonl,
  parseTarArchive,
} = require("../viewer/parser.js");

const encoder = new TextEncoder();

test("parseTarArchive reads zmrtrace entries with text and binary content", () => {
  const archive = makeTar([
    ["trace.json", JSON.stringify({ scenarioName: "demo", status: "passed" })],
    ["events.jsonl", '{"seq":1,"kind":"scenario.end","payload":{"status":"passed"}}\n'],
    ["artifacts/snapshot-1.png", new Uint8Array([0x89, 0x50, 0x4e, 0x47])],
  ]);

  const entries = parseTarArchive(archive.buffer);

  assert.deepEqual(entries.map((entry) => entry.path), [
    "trace.json",
    "events.jsonl",
    "artifacts/snapshot-1.png",
  ]);
  assert.equal(entries[0].text(), '{"scenarioName":"demo","status":"passed"}');
  assert.deepEqual([...entries[2].bytes], [0x89, 0x50, 0x4e, 0x47]);
});

test("parseEventsJsonl ignores blank lines and preserves malformed lines as parse errors", () => {
  const events = parseEventsJsonl(
    '{"seq":1,"kind":"scenario.start","payload":{"value":"demo"}}\n\nnot json\n',
  );

  assert.equal(events.length, 2);
  assert.equal(events[0].kind, "scenario.start");
  assert.equal(events[1].kind, "parse.error");
  assert.match(events[1].payload.message, /Unexpected token/);
});

test("buildTraceModel combines manifest events and artifacts for viewer rendering", () => {
  const archive = makeTar([
    ["trace.json", JSON.stringify({ scenarioName: "demo", status: "failed", eventCount: 2 })],
    [
      "events.jsonl",
      [
        '{"seq":1,"kind":"scenario.start","payload":{"value":"demo"}}',
        '{"seq":2,"kind":"wait.visible","payload":{"status":"timeout","snapshotId":"snapshot-1"}}',
      ].join("\n"),
    ],
    ["artifacts/snapshot-1.json", JSON.stringify({ id: "snapshot-1", nodes: [{ text: "Home" }] })],
  ]);

  const model = buildTraceModel(parseTarArchive(archive.buffer));

  assert.equal(model.manifest.scenarioName, "demo");
  assert.equal(model.summary.status, "failed");
  assert.equal(model.events.length, 2);
  assert.equal(model.artifacts.length, 1);
  assert.equal(model.snapshots.get("snapshot-1").nodes[0].text, "Home");
});

test("buildTraceModel links snapshots to screenshot and tree artifacts for inspection", () => {
  const archive = makeTar([
    ["trace.json", JSON.stringify({ scenarioName: "inspect", status: "failed", artifactsDir: "artifacts" })],
    [
      "events.jsonl",
      '{"seq":1,"kind":"wait.visible","payload":{"status":"timeout","snapshotId":"snapshot-1"}}\n',
    ],
    [
      "artifacts/snapshot-1.json",
      JSON.stringify({
        id: "snapshot-1",
        screenshotArtifact: "traces/run/artifacts/snapshot-1.png",
        treeArtifact: "traces/run/artifacts/snapshot-1.xml",
        nodes: [
          { stableId: "button-login", text: "Sign in", bounds: { x: 10, y: 20, width: 100, height: 44 } },
        ],
      }),
    ],
    ["artifacts/snapshot-1.png", new Uint8Array([0x89, 0x50, 0x4e, 0x47])],
    ["artifacts/snapshot-1.xml", "<hierarchy />"],
  ]);

  const model = buildTraceModel(parseTarArchive(archive.buffer));
  const inspection = model.snapshotInspections.get("snapshot-1");

  assert.equal(inspection.snapshot.id, "snapshot-1");
  assert.equal(inspection.screenshot.path, "artifacts/snapshot-1.png");
  assert.equal(inspection.tree.path, "artifacts/snapshot-1.xml");
  assert.equal(inspection.nodes[0].stableId, "button-login");
  assert.equal(inspection.nodes[0].label, "Sign in");
});

test("buildTraceModel derives replay frames from snapshot-linked events", () => {
  const archive = makeTar([
    ["trace.json", JSON.stringify({ scenarioName: "replay", status: "passed", artifactsDir: "artifacts" })],
    [
      "events.jsonl",
      [
        '{"seq":1,"timestampMs":1000,"kind":"scenario.start","payload":{"value":"replay"}}',
        '{"seq":2,"timestampMs":1100,"kind":"observe.snapshot","payload":{"value":"traces/run/artifacts/snapshot-1.json"}}',
        '{"seq":3,"timestampMs":1400,"kind":"ui.tap","payload":{"status":"ok","afterSnapshotId":"snapshot-2"}}',
        '{"seq":4,"timestampMs":1600,"kind":"wait.visible","payload":{"status":"ok","snapshotId":"missing-snapshot"}}',
        '{"seq":5,"timestampMs":1700,"kind":"scenario.end","payload":{"status":"passed"}}',
      ].join("\n"),
    ],
    ["artifacts/snapshot-1.json", JSON.stringify({ id: "snapshot-1", nodes: [{ text: "Login" }] })],
    ["artifacts/snapshot-1.png", new Uint8Array([0x89, 0x50, 0x4e, 0x47])],
    ["artifacts/snapshot-2.json", JSON.stringify({ id: "snapshot-2", nodes: [{ text: "Home" }] })],
    ["artifacts/snapshot-2.png", new Uint8Array([0x89, 0x50, 0x4e, 0x47])],
  ]);

  const model = buildTraceModel(parseTarArchive(archive.buffer));

  assert.deepEqual(
    model.replayFrames.map((frame) => ({
      index: frame.index,
      seq: frame.seq,
      kind: frame.kind,
      snapshotId: frame.snapshotId,
      elapsedMs: frame.elapsedMs,
      status: frame.status,
      nodeCount: frame.inspection.nodes.length,
    })),
    [
      { index: 0, seq: 2, kind: "observe.snapshot", snapshotId: "snapshot-1", elapsedMs: 100, status: "event", nodeCount: 1 },
      { index: 1, seq: 3, kind: "ui.tap", snapshotId: "snapshot-2", elapsedMs: 400, status: "ok", nodeCount: 1 },
    ],
  );
});

function makeTar(files) {
  const chunks = [];
  for (const [name, content] of files) {
    const bytes = typeof content === "string" ? encoder.encode(content) : content;
    const header = new Uint8Array(512);
    writeAscii(header, 0, 100, name);
    writeOctal(header, 100, 8, 0o644);
    writeOctal(header, 108, 8, 0);
    writeOctal(header, 116, 8, 0);
    writeOctal(header, 124, 12, bytes.length);
    writeOctal(header, 136, 12, 0);
    header.fill(0x20, 148, 156);
    header[156] = "0".charCodeAt(0);
    writeAscii(header, 257, 6, "ustar");
    writeAscii(header, 263, 2, "00");
    writeOctal(header, 148, 8, checksum(header));
    chunks.push(header, bytes, new Uint8Array((512 - (bytes.length % 512)) % 512));
  }
  chunks.push(new Uint8Array(1024));
  return concat(chunks);
}

function writeAscii(buffer, offset, length, value) {
  const bytes = encoder.encode(value);
  buffer.set(bytes.slice(0, length), offset);
}

function writeOctal(buffer, offset, length, value) {
  const encoded = value.toString(8).padStart(length - 1, "0");
  writeAscii(buffer, offset, length - 1, encoded);
}

function checksum(header) {
  return header.reduce((sum, byte) => sum + byte, 0);
}

function concat(chunks) {
  const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}
