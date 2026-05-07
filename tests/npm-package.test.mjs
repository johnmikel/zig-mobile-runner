import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import url from "node:url";

const root = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), "..");

test("package exposes zmr bin and public files for npm publishing", () => {
  const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));

  assert.equal(pkg.name, "zig-mobile-runner");
  assert.equal(pkg.repository.type, "git");
  assert.match(pkg.repository.url, /^git\+https:\/\/github\.com\/johnmikel\/zig-mobile-runner\.git$/);
  assert.match(pkg.homepage, /^https:\/\/github\.com\/johnmikel\/zig-mobile-runner#readme$/);
  assert.match(pkg.bugs.url, /^https:\/\/github\.com\/johnmikel\/zig-mobile-runner\/issues$/);
  assert.equal(pkg.bin.zmr, "npm/zmr.mjs");
  assert.equal(pkg.bin["zmr-benchmark"], "scripts/benchmark.sh");
  assert.equal(pkg.bin["zmr-device-matrix"], "scripts/device-matrix.sh");
  assert.equal(pkg.bin["zmr-pilot-gate"], "scripts/pilot-gate.sh");
  assert.equal(pkg.bin["zmr-install-android-shim"], "scripts/install-android-shim.sh");
  assert.equal(pkg.bin["zmr-install-ios-shim"], "scripts/install-ios-shim.sh");
  assert.equal(pkg.main, "npm/index.mjs");
  assert.ok(pkg.files.includes("npm/"));
  assert.ok(pkg.files.includes("clients/typescript/"));
  assert.ok(pkg.files.includes("clients/python/zmr_client.py"));
  assert.ok(pkg.files.includes("clients/go/"));
  assert.ok(pkg.files.includes("clients/rust/Cargo.toml"));
  assert.ok(pkg.files.includes("clients/rust/src/"));
  assert.ok(pkg.files.includes("clients/rust/examples/"));
  assert.ok(pkg.files.includes("src/"));
  assert.ok(pkg.files.includes("examples/"));
  assert.ok(pkg.files.includes("shims/"));
  assert.equal(pkg.scripts["zmr:demo"], "node npm/zmr.mjs validate examples/demo-fake.json");
});

test("npm prebuild packer respects release version overrides", () => {
  const script = fs.readFileSync(path.join(root, "scripts", "build-npm-package.sh"), "utf8");

  assert.match(script, /VERSION="\$\{ZMR_VERSION:-/);
  assert.match(script, /zmr-\$VERSION-\$target\/zmr/);
});

test("node API resolves environment binary and runs zmr", async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "zmr-npm-test-"));
  const fakeBin = path.join(tmp, "zmr");
  fs.writeFileSync(fakeBin, "#!/usr/bin/env sh\nprintf 'fake-zmr %s\\n' \"$*\"\n");
  fs.chmodSync(fakeBin, 0o755);

  const previous = process.env.ZMR_BIN;
  process.env.ZMR_BIN = fakeBin;
  try {
    const api = await import(url.pathToFileURL(path.join(root, "npm/index.mjs")));
    assert.equal(api.resolveBinary(), fakeBin);
    const result = spawnSync(process.execPath, [path.join(root, "npm/zmr.mjs"), "version"], {
      env: { ...process.env, ZMR_BIN: fakeBin },
      encoding: "utf8",
    });
    assert.equal(result.status, 0);
    assert.match(result.stdout, /fake-zmr version/);
  } finally {
    if (previous == null) delete process.env.ZMR_BIN;
    else process.env.ZMR_BIN = previous;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("init command creates app-local scenario and npm script snippets", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "zmr-init-test-"));
  try {
    const result = spawnSync(process.execPath, [
      path.join(root, "npm/init-app.mjs"),
      "--dir",
      tmp,
      "--app-id",
      "com.example.demo",
    ], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);

    const scenario = JSON.parse(fs.readFileSync(path.join(tmp, ".zmr", "android-smoke.json"), "utf8"));
    assert.equal(scenario.appId, "com.example.demo");
    assert.ok(fs.existsSync(path.join(tmp, ".zmr", "ios-smoke.json")));
    const config = JSON.parse(fs.readFileSync(path.join(tmp, ".zmr", "config.json"), "utf8"));
    assert.equal(config.schemaVersion, 1);
    assert.equal(config.appId, "com.example.demo");
    assert.equal(config.android.smokeScenario, ".zmr/android-smoke.json");
    assert.equal(config.ios.smokeScenario, ".zmr/ios-smoke.json");
    assert.equal(config.artifacts.screenshots, true);
    assert.equal(config.artifacts.hierarchy, true);
    assert.equal(config.artifacts.logs, true);
    assert.equal(config.artifacts.screenRecording, false);
    assert.equal(config.scripts.android, "zmr run .zmr/android-smoke.json --device emulator-5554 --trace-dir traces/zmr-android");
    assert.equal(
      config.scripts.androidReliability,
      "ZMR_BIN=${ZMR_BIN:-zmr} zmr-benchmark --zmr .zmr/android-smoke.json --device emulator-5554 --app-id com.example.demo --runs 20 --trace-root traces/zmr-android-reliability --min-pass-rate 100 --max-failures 0 --max-p95-ms 30000 && zmr report traces/zmr-android-reliability --out traces/zmr-android-reliability/report.html",
    );
    assert.equal(
      config.scripts.iosReliability,
      "ZMR_BIN=${ZMR_BIN:-zmr} zmr-benchmark --zmr .zmr/ios-smoke.json --platform ios --device booted --app-id com.example.demo --xcrun xcrun --runs 20 --trace-root traces/zmr-ios-reliability --min-pass-rate 100 --max-failures 0 --max-p95-ms 45000 && zmr report traces/zmr-ios-reliability --out traces/zmr-ios-reliability/report.html",
    );
    assert.equal(
      config.scripts.pilotGate,
      "zmr-pilot-gate --android --ios --android-app-root . --ios-app-path ./build/Debug-iphonesimulator/Sample.app --runs 20 --min-pass-rate 100 --max-failures 0",
    );
    assert.match(fs.readFileSync(path.join(tmp, ".gitignore"), "utf8"), /^traces\/$/m);
    assert.match(result.stdout, /zmr:android/);
    assert.match(result.stdout, /zmr:ios/);
    assert.match(result.stdout, /zmr:android:reliability/);
    assert.match(result.stdout, /zmr:ios:reliability/);
    assert.match(result.stdout, /zmr:pilot/);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("wizard checks necessities, scaffolds scenarios, and patches package scripts", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "zmr-wizard-test-"));
  try {
    fs.writeFileSync(path.join(tmp, "package.json"), JSON.stringify({ scripts: {} }, null, 2));
    const fakeBin = path.join(tmp, "zmr");
    fs.writeFileSync(fakeBin, "#!/usr/bin/env sh\nprintf 'zmr 0.0.0 test\\n'\n");
    fs.chmodSync(fakeBin, 0o755);

    const result = spawnSync(process.execPath, [
      path.join(root, "npm/wizard.mjs"),
      "--yes",
      "--dir",
      tmp,
      "--app-id",
      "com.example.demo",
      "--android",
      "--ios",
      "--package-json",
    ], {
      env: { ...process.env, ZMR_BIN: fakeBin, PATH: `${tmp}${path.delimiter}${process.env.PATH}` },
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /ZMR setup wizard/);
    assert.match(result.stdout, /zmr\s+ok/);
    assert.match(result.stdout, /Next steps/);

    const pkg = JSON.parse(fs.readFileSync(path.join(tmp, "package.json"), "utf8"));
    assert.equal(pkg.scripts["zmr:doctor"], "zmr doctor");
    assert.equal(pkg.scripts["zmr:android"], "zmr run .zmr/android-smoke.json --device emulator-5554 --trace-dir traces/zmr-android");
    assert.equal(pkg.scripts["zmr:ios"], "zmr run .zmr/ios-smoke.json --platform ios --device booted --trace-dir traces/zmr-ios");

    const config = JSON.parse(fs.readFileSync(path.join(tmp, ".zmr", "config.json"), "utf8"));
    assert.equal(config.appId, "com.example.demo");
    assert.equal(config.artifacts.screenshots, true);
    assert.equal(config.artifacts.screenRecording, false);
    assert.equal(config.scripts.serve, "zmr serve --transport stdio --device emulator-5554 --app-id com.example.demo");
    assert.equal(
      config.scripts.pilotGate,
      "zmr-pilot-gate --android --ios --android-app-root . --ios-app-path ./build/Debug-iphonesimulator/Sample.app --runs 20 --min-pass-rate 100 --max-failures 0",
    );
    assert.equal(pkg.scripts["zmr:android:reliability"], config.scripts.androidReliability);
    assert.equal(pkg.scripts["zmr:ios:reliability"], config.scripts.iosReliability);
    assert.equal(pkg.scripts["zmr:pilot"], config.scripts.pilotGate);
    assert.match(fs.readFileSync(path.join(tmp, ".gitignore"), "utf8"), /^traces\/$/m);

    const scenario = JSON.parse(fs.readFileSync(path.join(tmp, ".zmr", "android-smoke.json"), "utf8"));
    assert.equal(scenario.appId, "com.example.demo");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("wizard can configure an iOS shim path for selector-grade simulator runs", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "zmr-wizard-ios-shim-test-"));
  try {
    const fakeBin = path.join(tmp, "zmr");
    fs.writeFileSync(fakeBin, "#!/usr/bin/env sh\nprintf 'zmr 0.0.0 test\\n'\n");
    fs.chmodSync(fakeBin, 0o755);

    const result = spawnSync(process.execPath, [
      path.join(root, "npm/wizard.mjs"),
      "--yes",
      "--dir",
      tmp,
      "--app-id",
      "com.example.demo",
      "--ios",
      "--ios-shim",
      "./.zmr/ios-shim",
      "--package-json",
    ], {
      env: { ...process.env, ZMR_BIN: fakeBin, PATH: `${tmp}${path.delimiter}${process.env.PATH}` },
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr);
    const config = JSON.parse(fs.readFileSync(path.join(tmp, ".zmr", "config.json"), "utf8"));
    assert.equal(config.tools.iosShimPath, "./.zmr/ios-shim");
    assert.equal(config.scripts.ios, "zmr run .zmr/ios-smoke.json --platform ios --device booted --trace-dir traces/zmr-ios --ios-shim ./.zmr/ios-shim");
    assert.equal(
      config.scripts.iosReliability,
      "ZMR_BIN=${ZMR_BIN:-zmr} zmr-benchmark --zmr .zmr/ios-smoke.json --platform ios --device booted --app-id com.example.demo --xcrun xcrun --ios-shim ./.zmr/ios-shim --runs 20 --trace-root traces/zmr-ios-reliability --min-pass-rate 100 --max-failures 0 --max-p95-ms 45000 && zmr report traces/zmr-ios-reliability --out traces/zmr-ios-reliability/report.html",
    );
    assert.equal(
      config.scripts.pilotGate,
      "zmr-pilot-gate --ios --ios-app-path ./build/Debug-iphonesimulator/Sample.app --ios-shim ./.zmr/ios-shim --runs 20 --min-pass-rate 100 --max-failures 0",
    );

    const pkg = JSON.parse(fs.readFileSync(path.join(tmp, "package.json"), "utf8"));
    assert.equal(pkg.scripts["zmr:ios"], config.scripts.ios);
    assert.equal(pkg.scripts["zmr:ios:reliability"], config.scripts.iosReliability);
    assert.equal(pkg.scripts["zmr:pilot"], config.scripts.pilotGate);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("wizard can configure an Android shim path for native instrumentation runs", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "zmr-wizard-android-shim-test-"));
  try {
    const fakeBin = path.join(tmp, "zmr");
    fs.writeFileSync(fakeBin, "#!/usr/bin/env sh\nprintf 'zmr 0.0.0 test\\n'\n");
    fs.chmodSync(fakeBin, 0o755);

    const result = spawnSync(process.execPath, [
      path.join(root, "npm/wizard.mjs"),
      "--yes",
      "--dir",
      tmp,
      "--app-id",
      "com.example.demo",
      "--android",
      "--android-shim",
      "./.zmr/android-shim",
      "--package-json",
    ], {
      env: { ...process.env, ZMR_BIN: fakeBin, PATH: `${tmp}${path.delimiter}${process.env.PATH}` },
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr);
    const config = JSON.parse(fs.readFileSync(path.join(tmp, ".zmr", "config.json"), "utf8"));
    assert.equal(config.tools.androidShimPath, "./.zmr/android-shim");
    assert.equal(config.scripts.android, "zmr run .zmr/android-smoke.json --device emulator-5554 --trace-dir traces/zmr-android --android-shim ./.zmr/android-shim");
    assert.equal(
      config.scripts.androidReliability,
      "ZMR_BIN=${ZMR_BIN:-zmr} zmr-benchmark --zmr .zmr/android-smoke.json --device emulator-5554 --app-id com.example.demo --android-shim ./.zmr/android-shim --runs 20 --trace-root traces/zmr-android-reliability --min-pass-rate 100 --max-failures 0 --max-p95-ms 30000 && zmr report traces/zmr-android-reliability --out traces/zmr-android-reliability/report.html",
    );
    assert.equal(
      config.scripts.pilotGate,
      "zmr-pilot-gate --android --android-app-root . --runs 20 --min-pass-rate 100 --max-failures 0",
    );

    const pkg = JSON.parse(fs.readFileSync(path.join(tmp, "package.json"), "utf8"));
    assert.equal(pkg.scripts["zmr:android"], config.scripts.android);
    assert.equal(pkg.scripts["zmr:android:reliability"], config.scripts.androidReliability);
    assert.equal(pkg.scripts["zmr:pilot"], config.scripts.pilotGate);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("wizard is tool agnostic and keeps ZMR state under .zmr", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "zmr-wizard-agnostic-test-"));
  try {
    fs.mkdirSync(path.join(tmp, `.${"maes"}tro`));
    fs.writeFileSync(path.join(tmp, "package.json"), JSON.stringify({
      scripts: { e2e: `${"de"}tox test` },
      devDependencies: { [`${"de"}tox`]: "^20.0.0" },
    }, null, 2));
    const fakeBin = path.join(tmp, "zmr");
    fs.writeFileSync(fakeBin, "#!/usr/bin/env sh\nprintf 'zmr 0.0.0 test\\n'\n");
    fs.chmodSync(fakeBin, 0o755);

    const result = spawnSync(process.execPath, [
      path.join(root, "npm/wizard.mjs"),
      "--yes",
      "--dir",
      tmp,
      "--app-id",
      "com.example.demo",
    ], {
      env: { ...process.env, ZMR_BIN: fakeBin, PATH: `${tmp}${path.delimiter}${process.env.PATH}` },
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr);
    assert.doesNotMatch(result.stdout, /Detected existing mobile test setup/);
    assert.doesNotMatch(result.stdout, /migration path/i);

    const config = JSON.parse(fs.readFileSync(path.join(tmp, ".zmr", "config.json"), "utf8"));
    assert.equal(config.appId, "com.example.demo");
    assert.ok(fs.existsSync(path.join(tmp, ".zmr", "android-smoke.json")));
    assert.ok(fs.existsSync(path.join(tmp, ".zmr", "ios-smoke.json")));
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("packed npm package installs in a temp app and drives zmr through .zmr", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "zmr-packed-install-test-"));
  const npmEnv = { ...process.env, npm_config_cache: path.join(tmp, ".npm-cache") };
  try {
    const pack = spawnSync("npm", ["pack", "--pack-destination", tmp], {
      cwd: root,
      env: npmEnv,
      encoding: "utf8",
    });
    assert.equal(pack.status, 0, pack.stderr);
    const tarball = fs.readdirSync(tmp).find((name) => name.endsWith(".tgz"));
    assert.ok(tarball, "npm pack should create a tarball");
    const tarList = spawnSync("tar", ["-tf", path.join(tmp, tarball)], { encoding: "utf8" });
    assert.equal(tarList.status, 0, tarList.stderr);
    assert.match(tarList.stdout, /package\/scripts\/benchmark_gate\.py/);
    assert.match(tarList.stdout, /package\/scripts\/generate-release-manifest\.mjs/);
    assert.match(tarList.stdout, /package\/scripts\/verify-release-artifacts\.sh/);
    assert.match(tarList.stdout, /package\/scripts\/sign-macos-release\.sh/);
    assert.match(tarList.stdout, /package\/scripts\/notarize-macos-release\.sh/);
    assert.match(tarList.stdout, /package\/scripts\/pilot-gate\.sh/);
    assert.match(tarList.stdout, /package\/schemas\/release-manifest\.schema\.json/);
    assert.doesNotMatch(tarList.stdout, /__pycache__|\.pyc/);

    const appDir = path.join(tmp, "app");
    fs.mkdirSync(appDir);
    fs.writeFileSync(path.join(appDir, "package.json"), JSON.stringify({ private: true }, null, 2));
    const install = spawnSync("npm", ["install", "--ignore-scripts", path.join(tmp, tarball)], {
      cwd: appDir,
      env: npmEnv,
      encoding: "utf8",
    });
    assert.equal(install.status, 0, install.stderr);

    const fakeBin = path.join(tmp, "zmr");
    fs.writeFileSync(fakeBin, "#!/usr/bin/env sh\nprintf 'fake-zmr %s\\n' \"$*\"\n");
    fs.chmodSync(fakeBin, 0o755);

    const wizard = spawnSync("npx", [
      "zmr-wizard",
      "--yes",
      "--dir",
      appDir,
      "--app-id",
      "com.example.demo",
      "--android",
      "--ios",
    ], {
      cwd: appDir,
      env: { ...npmEnv, ZMR_BIN: fakeBin, PATH: `${tmp}${path.delimiter}${process.env.PATH}` },
      encoding: "utf8",
    });
    assert.equal(wizard.status, 0, wizard.stderr);
    assert.ok(fs.existsSync(path.join(appDir, ".zmr", "config.json")));
    assert.ok(fs.existsSync(path.join(appDir, ".zmr", "android-smoke.json")));

    const validate = spawnSync("npx", ["zmr", "validate", "node_modules/zig-mobile-runner/examples/demo-fake.json"], {
      cwd: appDir,
      env: { ...npmEnv, ZMR_BIN: fakeBin },
      encoding: "utf8",
    });
    assert.equal(validate.status, 0, validate.stderr);
    assert.match(validate.stdout, /fake-zmr validate/);

    const pilotGate = spawnSync("npx", [
      "zmr-pilot-gate",
      "--android",
      "--ios",
      "--android-app-root",
      ".",
      "--ios-app-path",
      "./build/Sample.app",
      "--ios-shim",
      "./.zmr/ios-shim",
      "--trace-root",
      "traces/pilot",
      "--dry-run",
    ], {
      cwd: appDir,
      env: npmEnv,
      encoding: "utf8",
    });
    assert.equal(pilotGate.status, 0, pilotGate.stderr);
    const realAppDir = fs.realpathSync(appDir);
    assert.match(pilotGate.stdout, /DRY RUN/);
    assert.match(pilotGate.stdout, /scripts\/run-android-pilot\.sh/);
    assert.match(pilotGate.stdout, /scripts\/run-ios-pilot\.sh/);
    assert.match(pilotGate.stdout, new RegExp(`--app-root ${realAppDir.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
    assert.match(pilotGate.stdout, new RegExp(`--app-path ${path.join(realAppDir, "build", "Sample.app").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
    assert.match(pilotGate.stdout, new RegExp(`--ios-shim ${path.join(realAppDir, ".zmr", "ios-shim").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
    assert.match(pilotGate.stdout, new RegExp(`--trace-root ${path.join(realAppDir, "traces", "pilot", "android").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
