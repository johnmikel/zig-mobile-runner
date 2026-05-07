import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export function rootDir() {
  return packageRoot;
}

export function resolveBinary(env = process.env, platform = process.platform, arch = process.arch) {
  if (env.ZMR_BIN) return env.ZMR_BIN;

  const exe = platform === "win32" ? "zmr.exe" : "zmr";
  const candidates = [
    path.join(packageRoot, "prebuilds", `${platform}-${arch}`, exe),
    path.join(packageRoot, "zig-out", "bin", exe),
    path.join(packageRoot, "dist", `zmr-${platform}-${arch}`, exe),
  ];

  for (const candidate of candidates) {
    if (isExecutable(candidate)) return candidate;
  }

  return null;
}

export function spawnZmr(args = [], options = {}) {
  const binary = resolveBinary(options.env ?? process.env);
  if (!binary) {
    throw new Error(missingBinaryMessage());
  }
  return spawn(binary, args, {
    stdio: options.stdio ?? "inherit",
    cwd: options.cwd,
    env: options.env,
  });
}

export function runZmr(args = [], options = {}) {
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawnZmr(args, options);
    } catch (error) {
      reject(error);
      return;
    }
    child.on("error", reject);
    child.on("exit", (code, signal) => {
      if (code === 0) resolve({ code, signal });
      else reject(new Error(`zmr exited with ${signal ?? code}`));
    });
  });
}

export function missingBinaryMessage() {
  return [
    "Could not find a zmr binary.",
    "Set ZMR_BIN=/path/to/zmr, run `npm run build:zmr`, or install a release package that includes prebuilt binaries.",
    `Package root: ${packageRoot}`,
    `Host: ${os.platform()} ${os.arch()}`,
  ].join("\n");
}

function isExecutable(candidate) {
  try {
    fs.accessSync(candidate, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}
