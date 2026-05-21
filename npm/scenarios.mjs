export function deviceMatrix(appId, android = true, ios = true, androidShim = "", iosShim = "") {
  const devices = [];
  if (android) {
    const androidDevice = {
      name: "android-emulator",
      platform: "android",
      serial: "emulator-5554",
      scenario: ".zmr/android-smoke.json",
      adb: "adb",
    };
    if (androidShim) androidDevice.androidShim = androidShim;
    devices.push(androidDevice);
  }
  if (ios) {
    const iosDevice = {
      name: "ios-simulator",
      platform: "ios",
      iosDeviceType: "simulator",
      serial: "booted",
      scenario: ".zmr/ios-smoke.json",
      xcrun: "xcrun",
    };
    if (iosShim) iosDevice.iosShim = iosShim;
    devices.push(iosDevice);
  }
  return {
    runs: 1,
    appId,
    devices,
  };
}

export function smokeScenario(name, appId) {
  return {
    name,
    appId,
    steps: [
      { action: "launch" },
      { action: "assertHealthy" },
      { action: "snapshot" },
    ],
  };
}

export function scenarioFiles(appId, { android = true, ios = true, expoDevClientScheme = "" } = {}) {
  const files = [];
  if (android) files.push({ path: "android-smoke.json", scenario: smokeScenario("Android smoke", appId) });
  if (ios) files.push({ path: "ios-smoke.json", scenario: smokeScenario("iOS smoke", appId) });
  if (expoDevClientScheme) {
    if (android) {
      files.push({
        path: "android-dev-client-smoke.json",
        scenario: devClientScenario("Android Expo dev-client smoke", appId, expoDevClientScheme, "http://10.0.2.2:8081"),
      });
    }
    if (ios) {
      files.push({
        path: "ios-dev-client-open-link.json",
        scenario: devClientScenario("iOS Expo dev-client open-link smoke", appId, expoDevClientScheme, "http://127.0.0.1:8081"),
      });
    }
  }
  return files;
}

export function devClientScenario(name, appId, scheme, metroUrl) {
  return {
    name,
    appId,
    steps: [
      { action: "stop" },
      {
        action: "openLink",
        url: `exp+${scheme}://expo-development-client/?url=${encodeURIComponent(metroUrl)}`,
      },
      {
        action: "waitAny",
        selectors: [
          { textContains: "Downloading" },
          { textContains: "Connected to:" },
          { textContains: "Reload" },
          { textContains: "Continue" },
          { textContains: "Sign in" },
          { textContains: "Home" },
          { textContains: "Unable to load" },
        ],
        timeoutMs: 120000,
      },
      { action: "assertHealthy" },
      { action: "snapshot" },
    ],
  };
}
