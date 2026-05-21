export function readOptionValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}

export function parseScaffoldArgs(args, { packageJson = false, wizard = false } = {}) {
  const parsed = {
    dir: process.cwd(),
    appId: "com.example.mobiletest",
    android: false,
    androidShim: "",
    ios: false,
    iosShim: "",
    expoDevClientScheme: "",
  };
  if (packageJson || wizard) {
    parsed.packageJson = false;
  }
  if (wizard) {
    parsed.yes = false;
  }
  parsed.json = false;

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") return { help: true };
    if (arg === "--dir") parsed.dir = readOptionValue(args, ++i, arg);
    else if (arg === "--app-id") parsed.appId = readOptionValue(args, ++i, arg);
    else if (arg === "--android") parsed.android = true;
    else if (arg === "--android-shim") parsed.androidShim = readOptionValue(args, ++i, arg);
    else if (arg === "--ios") parsed.ios = true;
    else if (arg === "--ios-shim") parsed.iosShim = readOptionValue(args, ++i, arg);
    else if (arg === "--expo-dev-client-scheme") parsed.expoDevClientScheme = readOptionValue(args, ++i, arg);
    else if (arg === "--json") parsed.json = true;
    else if ((packageJson || wizard) && arg === "--package-json") parsed.packageJson = true;
    else if (wizard && (arg === "--yes" || arg === "-y")) parsed.yes = true;
    else throw new Error(`unknown argument: ${arg}`);
  }

  if (!parsed.android && !parsed.ios) {
    parsed.android = true;
    parsed.ios = true;
  }
  return parsed;
}

export function wizardChecks({ android = true, ios = true, nodePath = process.execPath, zmrPath = "zmr" } = {}) {
  const checks = [
    { label: "node", command: nodePath, args: ["--version"], required: true },
    { label: "zmr", command: zmrPath || "zmr", args: ["version"], required: true },
  ];
  if (android) checks.push({ label: "adb", command: "adb", args: ["version"], required: false });
  if (ios) checks.push({ label: "xcrun", command: "xcrun", args: ["--version"], required: false });
  checks.push({ label: "zig", command: "zig", args: ["version"], required: false });
  return checks;
}

export function formatWizardCheckResult(label, result, { required = false } = {}) {
  if (result.status === 0) {
    const firstLine = (result.stdout || result.stderr || "").split(/\r?\n/).find(Boolean) ?? "ok";
    return `${label}\tok\t${firstLine}`;
  }
  const status = required ? "missing" : "warning";
  const detail = result.error?.message ?? `exit ${result.status ?? "unknown"}`;
  return `${label}\t${status}\t${detail}`;
}
