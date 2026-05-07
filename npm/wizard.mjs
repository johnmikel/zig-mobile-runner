#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";
import { resolveBinary } from "./index.mjs";

const options = parseArgs(process.argv.slice(2));

console.log("ZMR setup wizard");
console.log("================");

if (!options.yes) {
  await promptForMissingOptions(options);
}

const appRoot = path.resolve(options.dir);
fs.mkdirSync(path.join(appRoot, ".zmr"), { recursive: true });

console.log("");
console.log("Checking necessities");
check("node", process.execPath, ["--version"], { required: true });
check("zmr", resolveBinary() ?? "zmr", ["version"], { required: true });
check("adb", "adb", ["version"], { required: false, only: options.android });
check("xcrun", "xcrun", ["--version"], { required: false, only: options.ios });
check("zig", "zig", ["version"], { required: false });

writeConfig(appRoot, options.appId, options.android, options.ios);
writeScenarios(appRoot, options.appId, options.android, options.ios);
ensureTraceIgnore(appRoot);
if (options.packageJson) patchPackageJson(appRoot, options.android, options.ios);

console.log("");
console.log("Next steps");
if (options.android) {
  console.log("  npm run zmr:android");
  console.log("  npm run zmr:android:reliability");
}
if (options.ios) {
  console.log("  npm run zmr:ios");
  console.log("  npm run zmr:ios:reliability");
}
if (options.android || options.ios) {
  console.log("  npm run zmr:pilot");
}
console.log("  npm run zmr:doctor");

function parseArgs(args) {
  const parsed = {
    dir: process.cwd(),
    appId: "",
    android: false,
    androidShim: "",
    ios: false,
    iosShim: "",
    packageJson: false,
    yes: false,
  };

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === "--dir") parsed.dir = args[++i] ?? "";
    else if (arg === "--app-id") parsed.appId = args[++i] ?? "";
    else if (arg === "--android") parsed.android = true;
    else if (arg === "--android-shim") parsed.androidShim = args[++i] ?? "";
    else if (arg === "--ios") parsed.ios = true;
    else if (arg === "--ios-shim") parsed.iosShim = args[++i] ?? "";
    else if (arg === "--package-json") parsed.packageJson = true;
    else if (arg === "--yes" || arg === "-y") parsed.yes = true;
    else if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else {
      console.error(`unknown argument: ${arg}`);
      usage();
      process.exit(2);
    }
  }

  if (!parsed.android && !parsed.ios) {
    parsed.android = true;
    parsed.ios = true;
  }
  if (!parsed.appId) parsed.appId = "com.example.mobiletest";
  return parsed;
}

async function promptForMissingOptions(parsed) {
  const rl = readline.createInterface({ input, output });
  try {
    parsed.appId = (await rl.question(`App id [${parsed.appId}]: `)).trim() || parsed.appId;
    const patch = (await rl.question("Patch package.json scripts? [Y/n]: ")).trim().toLowerCase();
    parsed.packageJson = patch === "" || patch === "y" || patch === "yes";
  } finally {
    rl.close();
  }
}

function usage() {
  console.log("Usage: zmr-wizard [--dir <app-root>] [--app-id <id>] [--android] [--android-shim <path>] [--ios] [--ios-shim <path>] [--package-json] [--yes]");
}

function check(label, command, args, opts = {}) {
  if (opts.only === false) return;
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status === 0) {
    const firstLine = (result.stdout || result.stderr || "").split(/\r?\n/).find(Boolean) ?? "ok";
    console.log(`  ${label}\tok\t${firstLine}`);
    return;
  }
  const status = opts.required ? "missing" : "warning";
  const detail = result.error?.message ?? `exit ${result.status ?? "unknown"}`;
  console.log(`  ${label}\t${status}\t${detail}`);
}

function writeScenarios(root, appId, android, ios) {
  if (android) writeJson(path.join(root, ".zmr", "android-smoke.json"), smokeScenario("Android smoke", appId));
  if (ios) writeJson(path.join(root, ".zmr", "ios-smoke.json"), smokeScenario("iOS smoke", appId));
}

function writeConfig(root, appId, android, ios) {
  writeJson(path.join(root, ".zmr", "config.json"), zmrConfig(appId, android, ios, options.androidShim, options.iosShim));
}

function writeJson(file, value) {
  if (fs.existsSync(file)) return;
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
  console.log(`created ${path.relative(process.cwd(), file)}`);
}

function ensureTraceIgnore(root) {
  const file = path.join(root, ".gitignore");
  const existing = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
  if (/^traces\/$/m.test(existing)) return;
  const prefix = existing.length > 0 && !existing.endsWith("\n") ? "\n" : "";
  fs.writeFileSync(file, `${existing}${prefix}${existing.length > 0 ? "\n" : ""}# ZMR local run artifacts\ntraces/\n`);
  console.log(`updated ${path.relative(process.cwd(), file)}`);
}

function smokeScenario(name, appId) {
  return {
    name,
    appId,
    steps: [
      { action: "launch" },
      { action: "snapshot" },
    ],
  };
}

function zmrConfig(appId, android, ios, androidShim = "", iosShim = "") {
  const androidCommand = `zmr run .zmr/android-smoke.json --device emulator-5554 --trace-dir traces/zmr-android${androidShim ? ` --android-shim ${androidShim}` : ""}`;
  const iosCommand = `zmr run .zmr/ios-smoke.json --platform ios --device booted --trace-dir traces/zmr-ios${iosShim ? ` --ios-shim ${iosShim}` : ""}`;
  const androidReliability = reliabilityCommand({
    scenario: ".zmr/android-smoke.json",
    device: "emulator-5554",
    appId,
    androidShim,
    traceRoot: "traces/zmr-android-reliability",
    maxP95Ms: 30000,
  });
  const iosReliability = reliabilityCommand({
    scenario: ".zmr/ios-smoke.json",
    platform: "ios",
    device: "booted",
    appId,
    xcrun: "xcrun",
    iosShim,
    traceRoot: "traces/zmr-ios-reliability",
    maxP95Ms: 45000,
  });
  const config = {
    schemaVersion: 1,
    appId,
    android: {
      enabled: android,
      defaultDevice: "emulator-5554",
      smokeScenario: ".zmr/android-smoke.json",
      traceDir: "traces/zmr-android",
    },
    ios: {
      enabled: ios,
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
      android: androidCommand,
      androidReliability,
      ios: iosCommand,
      iosReliability,
      pilotGate: pilotGateCommand({ android, ios, iosShim }),
      serve: `zmr serve --transport stdio --device emulator-5554 --app-id ${appId}`,
    },
  };
  if (androidShim || iosShim) {
    config.tools = {};
    if (androidShim) config.tools.androidShimPath = androidShim;
    if (iosShim) config.tools.iosShimPath = iosShim;
  }
  return config;
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

function readConfig(root) {
  const file = path.join(root, ".zmr", "config.json");
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function patchPackageJson(root, android, ios) {
  const file = path.join(root, "package.json");
  const pkg = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
  const config = readConfig(root);
  pkg.scripts ??= {};
  pkg.scripts["zmr:doctor"] = config.scripts.doctor;
  if (android) {
    pkg.scripts["zmr:android"] = config.scripts.android;
    pkg.scripts["zmr:android:reliability"] = config.scripts.androidReliability;
  }
  if (ios) {
    pkg.scripts["zmr:ios"] = config.scripts.ios;
    pkg.scripts["zmr:ios:reliability"] = config.scripts.iosReliability;
  }
  pkg.scripts["zmr:pilot"] = config.scripts.pilotGate;
  pkg.scripts["zmr:serve"] = config.scripts.serve;
  fs.writeFileSync(file, `${JSON.stringify(pkg, null, 2)}\n`);
  console.log(`updated ${path.relative(process.cwd(), file)}`);
}
