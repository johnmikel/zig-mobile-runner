import fs from "node:fs";
import path from "node:path";
import { applyPackageScripts } from "./package-scripts.mjs";

export function ensureTraceIgnore(root, { cwd = process.cwd() } = {}) {
  const file = path.join(root, ".gitignore");
  const existing = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
  if (/^traces\/$/m.test(existing)) return null;
  const prefix = existing.length > 0 && !existing.endsWith("\n") ? "\n" : "";
  fs.writeFileSync(file, `${existing}${prefix}${existing.length > 0 ? "\n" : ""}# ZMR local run artifacts\ntraces/\n`);
  return path.relative(cwd, file);
}

export function writeJsonFile(file, value, { overwrite = false, cwd = process.cwd() } = {}) {
  return writeGeneratedFile(file, `${JSON.stringify(value, null, 2)}\n`, { overwrite, cwd });
}

export function writeTextFile(file, value, { overwrite = false, cwd = process.cwd() } = {}) {
  return writeGeneratedFile(file, value, { overwrite, cwd });
}

export function writeScaffoldFiles(root, files, { cwd = process.cwd() } = {}) {
  const results = [];
  for (const file of files) {
    const fullPath = path.join(root, file.path);
    fs.mkdirSync(path.dirname(fullPath), { recursive: true });
    const result = file.kind === "json"
      ? writeJsonFile(fullPath, file.value, { overwrite: file.overwrite, cwd })
      : writeTextFile(fullPath, file.value, { overwrite: file.overwrite, cwd });
    if (result) results.push(result);
  }
  return results;
}

export function writePackageScripts(root, config, { android = true, ios = true, cwd = process.cwd() } = {}) {
  const file = path.join(root, "package.json");
  const pkg = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
  fs.mkdirSync(path.dirname(file), { recursive: true });
  return writeJsonFile(file, applyPackageScripts(pkg, config, { android, ios }), { overwrite: true, cwd });
}

function writeGeneratedFile(file, value, { overwrite = false, cwd = process.cwd() } = {}) {
  const existed = fs.existsSync(file);
  if (existed && !overwrite) return null;
  fs.writeFileSync(file, value);
  return {
    path: path.relative(cwd, file),
    status: existed ? "updated" : "created",
  };
}
