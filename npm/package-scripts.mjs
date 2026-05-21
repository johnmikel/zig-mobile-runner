export function packageScripts(config) {
  return {
    "zmr:doctor": config.scripts.doctor,
    "zmr:schemas": config.scripts.schemas,
    "zmr:validate": config.scripts.validate,
    "zmr:android": config.scripts.android,
    "zmr:android:report": config.scripts.androidReport,
    "zmr:android:dev-client": config.scripts.androidDevClient,
    "zmr:android:dev-client:report": config.scripts.androidDevClientReport,
    "zmr:android:reliability": config.scripts.androidReliability,
    "zmr:ios": config.scripts.ios,
    "zmr:ios:report": config.scripts.iosReport,
    "zmr:ios:dev-client": config.scripts.iosDevClient,
    "zmr:ios:dev-client:report": config.scripts.iosDevClientReport,
    "zmr:ios:reliability": config.scripts.iosReliability,
    "zmr:matrix": config.scripts.matrix,
    "zmr:pilot": config.scripts.pilotGate,
    "zmr:readiness": config.scripts.readiness,
    "zmr:serve": config.scripts.serve,
    "zmr:mcp": config.scripts.mcp,
    "zmr:explain": config.scripts.explain,
    "zmr:export": config.scripts.exportTrace,
  };
}

export function applyPackageScripts(pkg, config, { android = true, ios = true } = {}) {
  pkg.scripts ??= {};
  const scripts = packageScripts(config);
  const setScript = (name, value) => {
    if (value == null) delete pkg.scripts[name];
    else pkg.scripts[name] = value;
  };

  setScript("zmr:doctor", scripts["zmr:doctor"]);
  setScript("zmr:schemas", scripts["zmr:schemas"]);
  setScript("zmr:validate", scripts["zmr:validate"]);
  if (android) {
    setScript("zmr:android", scripts["zmr:android"]);
    setScript("zmr:android:report", scripts["zmr:android:report"]);
    setScript("zmr:android:reliability", scripts["zmr:android:reliability"]);
    setScript("zmr:android:dev-client", config.scripts.androidDevClient);
    setScript("zmr:android:dev-client:report", config.scripts.androidDevClientReport);
  } else {
    setScript("zmr:android", null);
    setScript("zmr:android:report", null);
    setScript("zmr:android:reliability", null);
    setScript("zmr:android:dev-client", null);
    setScript("zmr:android:dev-client:report", null);
  }
  if (ios) {
    setScript("zmr:ios", scripts["zmr:ios"]);
    setScript("zmr:ios:report", scripts["zmr:ios:report"]);
    setScript("zmr:ios:reliability", scripts["zmr:ios:reliability"]);
    setScript("zmr:ios:dev-client", config.scripts.iosDevClient);
    setScript("zmr:ios:dev-client:report", config.scripts.iosDevClientReport);
  } else {
    setScript("zmr:ios", null);
    setScript("zmr:ios:report", null);
    setScript("zmr:ios:reliability", null);
    setScript("zmr:ios:dev-client", null);
    setScript("zmr:ios:dev-client:report", null);
  }
  if (android || ios) setScript("zmr:matrix", scripts["zmr:matrix"]);
  else setScript("zmr:matrix", null);
  setScript("zmr:pilot", scripts["zmr:pilot"]);
  setScript("zmr:readiness", config.scripts.readiness ? scripts["zmr:readiness"] : null);
  setScript("zmr:serve", scripts["zmr:serve"]);
  setScript("zmr:mcp", scripts["zmr:mcp"]);
  setScript("zmr:explain", scripts["zmr:explain"]);
  setScript("zmr:export", scripts["zmr:export"]);
  return pkg;
}
