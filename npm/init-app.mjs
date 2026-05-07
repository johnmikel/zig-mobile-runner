#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
let dir = process.cwd();
let appId = "com.example.mobiletest";

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i];
  if (arg === "--dir") {
    dir = args[++i];
  } else if (arg === "--app-id") {
    appId = args[++i];
  } else if (arg === "-h" || arg === "--help") {
    usage();
    process.exit(0);
  } else {
    console.error(`unknown argument: ${arg}`);
    usage();
    process.exit(2);
  }
}

if (!appId) {
  console.error("--app-id cannot be empty");
  process.exit(2);
}

const targetDir = path.resolve(dir, ".zmr");
fs.mkdirSync(targetDir, { recursive: true });
writeJson(path.join(targetDir, "config.json"), zmrConfig(appId));
writeJson(path.join(targetDir, "android-smoke.json"), androidScenario(appId));
writeJson(path.join(targetDir, "ios-smoke.json"), iosScenario(appId));
ensureTraceIgnore(path.resolve(dir));

console.log(`created ${path.relative(process.cwd(), targetDir)}`);
console.log("");
console.log("Add scripts like:");
console.log(JSON.stringify(packageScripts(zmrConfig(appId)), null, 2));

function usage() {
  console.log("Usage: zmr-init [--dir <app-root>] [--app-id <bundle-or-application-id>]");
}

function writeJson(file, value) {
  if (fs.existsSync(file)) return;
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function ensureTraceIgnore(root) {
  const file = path.join(root, ".gitignore");
  const existing = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
  if (/^traces\/$/m.test(existing)) return;
  const prefix = existing.length > 0 && !existing.endsWith("\n") ? "\n" : "";
  fs.writeFileSync(file, `${existing}${prefix}${existing.length > 0 ? "\n" : ""}# ZMR local run artifacts\ntraces/\n`);
}

function zmrConfig(id) {
  const androidReliability = reliabilityCommand({
    scenario: ".zmr/android-smoke.json",
    device: "emulator-5554",
    appId: id,
    traceRoot: "traces/zmr-android-reliability",
    maxP95Ms: 30000,
  });
  const iosReliability = reliabilityCommand({
    scenario: ".zmr/ios-smoke.json",
    platform: "ios",
    device: "booted",
    appId: id,
    xcrun: "xcrun",
    traceRoot: "traces/zmr-ios-reliability",
    maxP95Ms: 45000,
  });
  return {
    schemaVersion: 1,
    appId: id,
    android: {
      enabled: true,
      defaultDevice: "emulator-5554",
      smokeScenario: ".zmr/android-smoke.json",
      traceDir: "traces/zmr-android",
    },
    ios: {
      enabled: true,
      defaultDevice: "booted",
      smokeScenario: ".zmr/ios-smoke.json",
      traceDir: "traces/zmr-ios",
    },
    artifacts: {
      screenshots: true,
      hierarchy: true,
      logs: true,
      screenRecording: false,
    },
    scripts: {
      doctor: "zmr doctor",
      android: "zmr run .zmr/android-smoke.json --device emulator-5554 --trace-dir traces/zmr-android",
      androidReliability,
      ios: "zmr run .zmr/ios-smoke.json --platform ios --device booted --trace-dir traces/zmr-ios",
      iosReliability,
      pilotGate: pilotGateCommand({ android: true, ios: true }),
      serve: `zmr serve --transport stdio --device emulator-5554 --app-id ${id}`,
    },
  };
}

function packageScripts(config) {
  return {
    "zmr:doctor": config.scripts.doctor,
    "zmr:android": config.scripts.android,
    "zmr:android:reliability": config.scripts.androidReliability,
    "zmr:ios": config.scripts.ios,
    "zmr:ios:reliability": config.scripts.iosReliability,
    "zmr:pilot": config.scripts.pilotGate,
    "zmr:serve": config.scripts.serve,
  };
}

function pilotGateCommand({ android, ios, iosShim = "" }) {
  const args = ["zmr-pilot-gate"];
  if (android) args.push("--android");
  if (ios) args.push("--ios");
  if (android) args.push("--android-app-root", ".");
  if (ios) {
    args.push("--ios-app-path", "./build/Debug-iphonesimulator/Sample.app");
    if (iosShim) args.push("--ios-shim", iosShim);
  }
  args.push("--runs", "20", "--min-pass-rate", "100", "--max-failures", "0");
  return args.join(" ");
}

function reliabilityCommand({ scenario, platform = "", device, appId, xcrun = "", androidShim = "", iosShim = "", traceRoot, maxP95Ms }) {
  const args = [
    "ZMR_BIN=${ZMR_BIN:-zmr}",
    "zmr-benchmark",
    "--zmr",
    scenario,
  ];
  if (platform) args.push("--platform", platform);
  args.push("--device", device, "--app-id", appId);
  if (xcrun) args.push("--xcrun", xcrun);
  if (androidShim) args.push("--android-shim", androidShim);
  if (iosShim) args.push("--ios-shim", iosShim);
  args.push(
    "--runs",
    "20",
    "--trace-root",
    traceRoot,
    "--min-pass-rate",
    "100",
    "--max-failures",
    "0",
    "--max-p95-ms",
    String(maxP95Ms),
  );
  return `${args.join(" ")} && zmr report ${traceRoot} --out ${traceRoot}/report.html`;
}

function androidScenario(id) {
  return {
    name: "Android smoke",
    appId: id,
    steps: [
      { action: "launch" },
      { action: "snapshot" },
    ],
  };
}

function iosScenario(id) {
  return {
    name: "iOS smoke",
    appId: id,
    steps: [
      { action: "launch" },
      { action: "snapshot" },
    ],
  };
}
