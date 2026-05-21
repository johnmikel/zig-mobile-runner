#!/usr/bin/env node
import path from "node:path";
import {
  appInitOutput,
  ensureTraceIgnore,
  nextStepCommands,
  packageScripts,
  parseScaffoldArgs,
  scaffoldPlan,
  writePackageScripts,
  writeScaffoldFiles,
} from "./scaffold.mjs";

const options = parseArgs(process.argv.slice(2));
const {
  dir,
  appId,
  android,
  androidShim,
  ios,
  iosShim,
  expoDevClientScheme,
  packageJson,
} = options;

if (!appId) {
  console.error("--app-id cannot be empty");
  process.exit(2);
}

const targetDir = path.resolve(dir, ".zmr");
const appRoot = path.resolve(dir);
const plan = scaffoldPlan(appId, { android, ios, androidShim, iosShim, expoDevClientScheme, packageScripts: packageJson });
const { config, files } = plan;
writeScaffoldFiles(targetDir, files);
ensureTraceIgnore(appRoot);
if (packageJson) {
  const result = writePackageScripts(appRoot, config, { android, ios, cwd: appRoot });
  if (result && !options.json) console.log(`${result.status} ${result.path}`);
}

if (options.json) {
  process.stdout.write(`${JSON.stringify(appInitOutput(appRoot, appId, plan, { packageScripts: packageJson }))}\n`);
  process.exit(0);
}

console.log(`created ${path.relative(appRoot, targetDir)}`);
console.log("");
console.log("Next steps");
printNextSteps(config.scripts, { packageScripts: packageJson });
console.log("");
if (!packageJson) {
  console.log("Add scripts like:");
  console.log(JSON.stringify(packageScripts(config), null, 2));
}

function usage() {
  console.log("Usage: zmr-init [--dir <app-root>] [--app-id <bundle-or-application-id>] [--android] [--android-shim <path>] [--ios] [--ios-shim <path>] [--expo-dev-client-scheme <scheme>] [--package-json] [--json]");
}

function parseArgs(args) {
  try {
    const parsed = parseScaffoldArgs(args, { packageJson: true });
    if (parsed.help) {
      usage();
      process.exit(0);
    }
    return parsed;
  } catch (error) {
    console.error(error.message);
    usage();
    process.exit(2);
  }
}

function printNextSteps(scripts, { packageScripts: usePackageScripts = false } = {}) {
  for (const step of nextStepCommands({ scripts }, { android, ios, packageScripts: usePackageScripts })) {
    console.log(`  ${step.command}`);
  }
}
