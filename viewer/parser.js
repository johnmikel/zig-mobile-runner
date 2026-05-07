(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.ZmrTraceParser = api;
})(typeof globalThis !== "undefined" ? globalThis : window, function () {
  const decoder = new TextDecoder();

  function parseTarArchive(buffer) {
    const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
    const entries = [];
    let offset = 0;

    while (offset + 512 <= bytes.length) {
      const header = bytes.subarray(offset, offset + 512);
      if (isZeroBlock(header)) break;

      const name = readString(header, 0, 100);
      const prefix = readString(header, 345, 155);
      const path = prefix ? `${prefix}/${name}` : name;
      const sizeText = readString(header, 124, 12).trim();
      const size = sizeText ? Number.parseInt(sizeText, 8) : 0;
      if (!Number.isFinite(size) || size < 0) {
        throw new Error(`Invalid tar size for ${path || "<unknown>"}`);
      }

      const dataStart = offset + 512;
      const dataEnd = dataStart + size;
      if (dataEnd > bytes.length) {
        throw new Error(`Unexpected end of archive while reading ${path}`);
      }

      const entryBytes = bytes.slice(dataStart, dataEnd);
      entries.push({
        path,
        bytes: entryBytes,
        text: () => decoder.decode(entryBytes),
        mime: mimeForPath(path),
      });
      offset = dataStart + align512(size);
    }

    return entries;
  }

  function parseEventsJsonl(content) {
    const events = [];
    for (const rawLine of content.split(/\r?\n/)) {
      const line = rawLine.trim();
      if (!line) continue;
      try {
        events.push(JSON.parse(line));
      } catch (error) {
        events.push({
          seq: events.length + 1,
          timestampMs: null,
          kind: "parse.error",
          payload: {
            message: error instanceof Error ? error.message : String(error),
            line,
          },
        });
      }
    }
    return events;
  }

  function buildTraceModel(entries) {
    const byPath = new Map(entries.map((entry) => [entry.path, entry]));
    const manifestEntry = byPath.get("trace.json");
    if (!manifestEntry) throw new Error("trace.json is missing from this bundle");
    const manifest = JSON.parse(manifestEntry.text());
    const eventsEntry = byPath.get(manifest.eventsPath || "events.jsonl");
    const events = eventsEntry ? parseEventsJsonl(eventsEntry.text()) : [];
    const artifacts = entries
      .filter((entry) => entry.path.startsWith(`${manifest.artifactsDir || "artifacts"}/`))
      .map((entry) => ({
        path: entry.path,
        name: entry.path.split("/").at(-1),
        mime: entry.mime,
        entry,
      }));
    const snapshots = new Map();
    for (const artifact of artifacts) {
      if (!artifact.path.endsWith(".json")) continue;
      try {
        const snapshot = JSON.parse(artifact.entry.text());
        if (snapshot && typeof snapshot.id === "string") snapshots.set(snapshot.id, snapshot);
      } catch {
        // Non-snapshot JSON artifacts stay visible in the artifact list.
      }
    }
    const snapshotInspections = buildSnapshotInspections(snapshots, artifacts);
    const replayFrames = buildReplayFrames(events, snapshotInspections);

    return {
      manifest,
      events,
      artifacts,
      snapshots,
      snapshotInspections,
      replayFrames,
      entriesByPath: byPath,
      summary: {
        scenarioName: manifest.scenarioName || "",
        appId: manifest.appId || "",
        status: manifest.status || inferStatus(events),
        durationMs: manifest.durationMs ?? null,
        eventCount: manifest.eventCount ?? events.length,
        snapshotCount: manifest.snapshotCount ?? snapshots.size,
        failedStepIndex: manifest.failedStepIndex ?? null,
        error: manifest.error ?? null,
      },
    };
  }

  function buildReplayFrames(events, snapshotInspections) {
    const startTimestampMs = firstTimestamp(events);
    const frames = [];
    for (const event of events) {
      const snapshotId = snapshotIdForEvent(event);
      if (!snapshotId) continue;
      const inspection = snapshotInspections.get(snapshotId);
      if (!inspection) continue;
      const timestampMs = typeof event.timestampMs === "number" ? event.timestampMs : null;
      frames.push({
        index: frames.length,
        seq: event.seq ?? null,
        timestampMs,
        elapsedMs: timestampMs == null || startTimestampMs == null ? null : Math.max(0, timestampMs - startTimestampMs),
        kind: event.kind ?? "unknown",
        status: event.payload?.status ?? (event.payload?.error ? "error" : "event"),
        snapshotId,
        event,
        inspection,
      });
    }
    return frames;
  }

  function snapshotIdForEvent(event) {
    if (event.payload?.snapshotId) return event.payload.snapshotId;
    if (event.payload?.afterSnapshotId) return event.payload.afterSnapshotId;
    if (event.payload?.beforeSnapshotId) return event.payload.beforeSnapshotId;
    if (typeof event.payload?.value === "string") {
      const match = event.payload.value.match(/(?:^|\/)(snapshot-[^/.]+)\.json$/);
      if (match) return match[1];
    }
    return null;
  }

  function firstTimestamp(events) {
    for (const event of events) {
      if (typeof event.timestampMs === "number") return event.timestampMs;
    }
    return null;
  }

  function buildSnapshotInspections(snapshots, artifacts) {
    const byId = new Map();
    for (const [id, snapshot] of snapshots) {
      const screenshot = artifactForSnapshot(artifacts, snapshot.screenshotArtifact, id, ".png");
      const tree = artifactForSnapshot(artifacts, snapshot.treeArtifact, id, ".xml");
      byId.set(id, {
        id,
        snapshot,
        screenshot,
        tree,
        nodes: Array.isArray(snapshot.nodes) ? snapshot.nodes.map(normalizeNode) : [],
      });
    }
    return byId;
  }

  function artifactForSnapshot(artifacts, artifactPath, snapshotId, extension) {
    if (typeof artifactPath === "string" && artifactPath) {
      const byExact = artifacts.find((artifact) => artifact.path === artifactPath || artifactPath.endsWith(artifact.path));
      if (byExact) return byExact;
    }
    return artifacts.find((artifact) => artifact.path.endsWith(`${snapshotId}${extension}`)) ?? null;
  }

  function normalizeNode(node) {
    return {
      stableId: node.stableId ?? node.id ?? "",
      label: node.text ?? node.contentDesc ?? node.label ?? node.identifier ?? "",
      className: node.className ?? node.type ?? "",
      resourceId: node.resourceId ?? node.identifier ?? "",
      enabled: node.enabled !== false,
      visible: node.visible !== false,
      selected: node.selected === true,
      bounds: node.bounds ?? null,
      raw: node,
    };
  }

  function inferStatus(events) {
    for (let index = events.length - 1; index >= 0; index -= 1) {
      const event = events[index];
      if (event.kind === "scenario.end" && event.payload?.status) return event.payload.status;
    }
    return "unknown";
  }

  function align512(value) {
    return Math.ceil(value / 512) * 512;
  }

  function isZeroBlock(bytes) {
    return bytes.every((byte) => byte === 0);
  }

  function readString(bytes, offset, length) {
    const slice = bytes.subarray(offset, offset + length);
    const nul = slice.indexOf(0);
    const actual = nul === -1 ? slice : slice.subarray(0, nul);
    return decoder.decode(actual);
  }

  function mimeForPath(path) {
    if (path.endsWith(".png")) return "image/png";
    if (path.endsWith(".jpg") || path.endsWith(".jpeg")) return "image/jpeg";
    if (path.endsWith(".json")) return "application/json";
    if (path.endsWith(".xml")) return "application/xml";
    if (path.endsWith(".html")) return "text/html";
    return "application/octet-stream";
  }

  return {
    buildTraceModel,
    parseEventsJsonl,
    parseTarArchive,
  };
});
