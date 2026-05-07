#!/usr/bin/env node
import { spawnZmr, missingBinaryMessage } from "./index.mjs";

let child;
try {
  child = spawnZmr(process.argv.slice(2), { stdio: "inherit" });
} catch (error) {
  console.error(error?.message || missingBinaryMessage());
  process.exit(127);
}

child.on("error", (error) => {
  console.error(error?.message || String(error));
  process.exit(127);
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 1);
});
