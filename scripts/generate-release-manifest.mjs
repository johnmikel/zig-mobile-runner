#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function parseArgs(argv) {
  const args = {
    dist: path.join(root, "dist"),
    out: null,
    version: null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--dist") {
      args.dist = path.resolve(argv[++index] ?? "");
    } else if (arg === "--out") {
      args.out = path.resolve(argv[++index] ?? "");
    } else if (arg === "--version") {
      args.version = argv[++index] ?? "";
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }

  if (!args.version) throw new Error("--version is required");
  if (!args.out) args.out = path.join(args.dist, "RELEASE_MANIFEST.json");
  return args;
}

async function readJson(relativePath) {
  return JSON.parse(await readFile(path.join(root, relativePath), "utf8"));
}

function releaseTargetFromArchive(fileName, version) {
  const prefix = `zmr-${version}-`;
  const suffix = ".tar.gz";
  if (!fileName.startsWith(prefix) || !fileName.endsWith(suffix)) return {};

  const target = fileName.slice(prefix.length, fileName.length - suffix.length);
  const separator = target.indexOf("-");
  if (separator === -1) return { target };

  const arch = target.slice(0, separator);
  const rest = target.slice(separator + 1);
  const platform = rest.startsWith("macos") ? "macos" : rest.startsWith("linux") ? "linux" : rest.split(".")[0];
  return { target, platform, arch };
}

function artifactType(relativePath) {
  if (relativePath.endsWith(".tar.gz")) return "archive";
  if (relativePath.endsWith(".tgz")) return "npm-package";
  if (relativePath === "SBOM.spdx.json") return "sbom";
  if (relativePath === "THIRD_PARTY_NOTICES.md") return "notices";
  if (relativePath === "homebrew/zmr.rb") return "homebrew-formula";
  if (relativePath.startsWith("notarization/") && relativePath.endsWith(".notary.json")) return "notarization-receipt";
  return "metadata";
}

async function artifactFor(dist, relativePath, version) {
  if (relativePath.startsWith("/") || relativePath.includes("..")) {
    throw new Error(`unsafe release artifact path: ${relativePath}`);
  }

  const fullPath = path.join(dist, relativePath);
  let bytes;
  let fileStat;
  try {
    [bytes, fileStat] = await Promise.all([readFile(fullPath), stat(fullPath)]);
  } catch (error) {
    if (error.code === "ENOENT") throw new Error(`missing release artifact: ${relativePath}`);
    throw error;
  }
  if (!fileStat.isFile()) throw new Error(`release artifact is not a file: ${relativePath}`);

  const artifact = {
    path: relativePath,
    type: artifactType(relativePath),
    sizeBytes: fileStat.size,
    sha256: createHash("sha256").update(bytes).digest("hex"),
  };

  if (artifact.type === "archive") {
    Object.assign(artifact, releaseTargetFromArchive(path.basename(relativePath), version));
  }

  return artifact;
}

const { dist, out, version } = parseArgs(process.argv.slice(2));
const packageJson = await readJson("package.json");
const entries = await readdir(dist, { withFileTypes: true });
const archives = entries
  .filter((entry) => entry.isFile() && entry.name.endsWith(".tar.gz"))
  .map((entry) => entry.name)
  .sort();
const npmPackages = entries
  .filter((entry) => entry.isFile() && entry.name.endsWith(".tgz"))
  .map((entry) => entry.name)
  .sort();

if (archives.length === 0) throw new Error(`no release archives found in ${dist}`);

const requiredMetadata = ["SBOM.spdx.json", "THIRD_PARTY_NOTICES.md", "homebrew/zmr.rb"];
let notarizationReceipts = [];
try {
  notarizationReceipts = (await readdir(path.join(dist, "notarization"), { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith(".notary.json"))
    .map((entry) => `notarization/${entry.name}`)
    .sort();
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}

const artifactPaths = [...archives, ...npmPackages, ...requiredMetadata, ...notarizationReceipts];
const artifacts = [];
for (const artifactPath of artifactPaths) {
  artifacts.push(await artifactFor(dist, artifactPath, version));
}

const totalSizeBytes = artifacts.reduce((sum, artifact) => sum + artifact.sizeBytes, 0);
const manifest = {
  schemaVersion: 1,
  name: packageJson.name,
  version,
  generatedAt: new Date().toISOString(),
  releaseBaseUrl: process.env.ZMR_RELEASE_BASE_URL ?? null,
  artifacts,
  totals: {
    artifacts: artifacts.length,
    archives: archives.length,
    sizeBytes: totalSizeBytes,
  },
};

await writeFile(out, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`wrote ${out}`);
