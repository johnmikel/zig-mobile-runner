#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT=""
APP_ID="com.example.mobiletest"
API="35"
BUILD_TOOLS="35.0.1"
ANDROID_SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/create-android-demo-app.sh --out <dir> [options]

Creates a small public native Android demo app and a matching .zmr smoke
scenario. The generated app is intentionally generic and contains no private
app references. It uses Android SDK command-line tools directly, so it does not
need Gradle or network access.

Options:
  --out <dir>             Output app repository directory. Required.
  --app-id <id>           Android application id. Default: com.example.mobiletest.
  --api <level>           Android platform API level. Default: 35.
  --build-tools <ver>     Android build-tools version. Default: 35.0.1.
  --android-sdk <path>    Android SDK root. Default: ANDROID_HOME or ~/Library/Android/sdk.
  --dry-run               Print commands without executing them.
  -h, --help              Show this help.

After generation:
  adb install -r <dir>/build/app-debug.apk
  zmr run <dir>/.zmr/android-smoke.json --device emulator-5554 --app-id com.example.mobiletest --trace-dir <dir>/traces/android-demo
USAGE
}

die() {
  echo "error: $*" >&2
  exit 2
}

require_value() {
  local flag="$1"
  local value="${2-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    die "$flag requires a value"
  fi
  printf '%s\n' "$value"
}

quote_cmd() {
  local quoted=()
  local arg
  for arg in "$@"; do
    quoted+=("$(printf '%q' "$arg")")
  done
  printf '%s\n' "${quoted[*]}"
}

run() {
  echo "+ $(quote_cmd "$@")"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$@"
  fi
}

write_file() {
  local path="$1"
  local content="$2"
  echo "+ write $path"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$(dirname "$path")"
    printf '%s' "$content" > "$path"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --app-id)
      APP_ID="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --api)
      API="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --build-tools)
      BUILD_TOOLS="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --android-sdk)
      ANDROID_SDK="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$OUT" ]] || die "--out is required"
[[ "$APP_ID" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]] || die "--app-id must be a Java-style package id"
[[ "$API" =~ ^[0-9]+$ ]] || die "--api must be an integer"
[[ -n "$BUILD_TOOLS" ]] || die "--build-tools must be non-empty"

if [[ "$OUT" != /* ]]; then
  OUT="$(pwd -P)/$OUT"
fi

ANDROID_DIR="$OUT/android"
SRC_DIR="$ANDROID_DIR/src/dev/zmr/demo"
RES_DIR="$ANDROID_DIR/res"
BUILD_DIR="$OUT/build"
GEN_DIR="$BUILD_DIR/generated"
CLASSES_DIR="$BUILD_DIR/classes"
DEX_DIR="$BUILD_DIR/dex"
COMPILED_RES="$BUILD_DIR/compiled-res.zip"
UNSIGNED_APK="$BUILD_DIR/app-unsigned.apk"
SIGNED_APK="$BUILD_DIR/app-debug.apk"
KEYSTORE="$BUILD_DIR/debug.keystore"
ANDROID_JAR="$ANDROID_SDK/platforms/android-$API/android.jar"
BUILD_TOOLS_DIR="$ANDROID_SDK/build-tools/$BUILD_TOOLS"
AAPT2="$BUILD_TOOLS_DIR/aapt2"
D8="$BUILD_TOOLS_DIR/d8"
APKSIGNER="$BUILD_TOOLS_DIR/apksigner"
ZMR_BIN="${ZMR_BIN:-}"

echo "Android demo app: $OUT"
echo "Android demo APK: $SIGNED_APK"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN: commands will be printed but not executed"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  [[ -f "$ANDROID_JAR" ]] || die "android.jar not found: $ANDROID_JAR"
  [[ -x "$AAPT2" ]] || die "aapt2 not found: $AAPT2"
  [[ -x "$D8" ]] || die "d8 not found: $D8"
  [[ -x "$APKSIGNER" ]] || die "apksigner not found: $APKSIGNER"
  command -v javac >/dev/null 2>&1 || die "javac is required"
  command -v keytool >/dev/null 2>&1 || die "keytool is required"
  command -v zip >/dev/null 2>&1 || die "zip is required"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  rm -rf "$BUILD_DIR"
fi
run mkdir -p "$SRC_DIR" "$RES_DIR/values" "$BUILD_DIR" "$GEN_DIR" "$CLASSES_DIR" "$DEX_DIR" "$OUT/.zmr"

write_file "$ANDROID_DIR/AndroidManifest.xml" "$(cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$APP_ID">
  <uses-sdk android:minSdkVersion="23" android:targetSdkVersion="$API" />
  <application android:theme="@style/AppTheme" android:label="ZMR Android Demo" android:allowBackup="false" android:supportsRtl="true">
    <activity android:name="dev.zmr.demo.MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
      </intent-filter>
      <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="exampleapp" />
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF
)"

write_file "$RES_DIR/values/styles.xml" "$(cat <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
  <style name="AppTheme" parent="android:style/Theme.Material.Light.NoActionBar">
    <item name="android:fontFamily">sans</item>
    <item name="android:windowLightStatusBar">true</item>
    <item name="android:colorAccent">#2563EB</item>
  </style>
</resources>
EOF
)"

write_file "$RES_DIR/values/ids.xml" "$(cat <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
  <item name="demo_title" type="id" />
  <item name="continue_button" type="id" />
  <item name="demo_input" type="id" />
  <item name="demo_status" type="id" />
</resources>
EOF
)"

write_file "$SRC_DIR/MainActivity.java" "$(cat <<EOF
package dev.zmr.demo;

import android.app.Activity;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.view.Gravity;
import android.view.inputmethod.InputMethodManager;
import android.content.Context;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

public class MainActivity extends Activity {
    private TextView status;
    private EditText input;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setGravity(Gravity.CENTER_HORIZONTAL);
        int padding = dp(24);
        layout.setPadding(padding, padding, padding, padding);

        TextView title = new TextView(this);
        title.setId(R.id.demo_title);
        title.setText("ZMR Android Demo");
        title.setTextSize(24);
        title.setTextColor(Color.rgb(17, 24, 39));
        title.setGravity(Gravity.CENTER);
        layout.addView(title, new LinearLayout.LayoutParams(-1, -2));

        Button button = new Button(this);
        button.setId(R.id.continue_button);
        button.setText("Continue");
        layout.addView(button, new LinearLayout.LayoutParams(-1, dp(56)));

        input = new EditText(this);
        input.setId(R.id.demo_input);
        input.setHint("Type here");
        input.setSingleLine(true);
        layout.addView(input, new LinearLayout.LayoutParams(-1, dp(56)));

        status = new TextView(this);
        status.setId(R.id.demo_status);
        status.setText("Ready");
        status.setTextSize(18);
        status.setGravity(Gravity.CENTER);
        layout.addView(status, new LinearLayout.LayoutParams(-1, -2));

        button.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                status.setText("Continue tapped");
                input.requestFocus();
                InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
                if (imm != null) {
                    imm.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT);
                }
            }
        });

        Uri data = getIntent().getData();
        if (data != null) {
            status.setText("Deep link opened");
        }

        setContentView(layout);
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }
}
EOF
)"

write_file "$OUT/.zmr/android-smoke.json" "$(cat <<EOF
{
  "name": "ZMR Android demo smoke",
  "appId": "$APP_ID",
  "steps": [
    { "action": "launch" },
    { "action": "waitVisible", "selector": { "text": "ZMR Android Demo" }, "timeoutMs": 30000 },
    { "action": "tap", "selector": { "resourceId": "$APP_ID:id/continue_button" } },
    { "action": "waitVisible", "selector": { "text": "Continue tapped" }, "timeoutMs": 10000 },
    { "action": "typeText", "selector": { "resourceId": "$APP_ID:id/demo_input" }, "text": "hello from zmr" },
    { "action": "snapshot" }
  ]
}
EOF
)"

run "$AAPT2" compile --dir "$RES_DIR" -o "$COMPILED_RES"
run "$AAPT2" link -o "$UNSIGNED_APK" -I "$ANDROID_JAR" --manifest "$ANDROID_DIR/AndroidManifest.xml" -R "$COMPILED_RES" --java "$GEN_DIR" --custom-package dev.zmr.demo --auto-add-overlay
run javac -source 1.8 -target 1.8 -bootclasspath "$ANDROID_JAR" -d "$CLASSES_DIR" "$GEN_DIR/dev/zmr/demo/R.java" "$SRC_DIR/MainActivity.java"
if [[ "$DRY_RUN" -eq 1 ]]; then
  CLASS_FILES=(
    "$CLASSES_DIR/dev/zmr/demo/R.class"
    "$CLASSES_DIR/dev/zmr/demo/MainActivity.class"
    "$CLASSES_DIR/dev/zmr/demo/MainActivity\$1.class"
  )
else
  CLASS_FILES=()
  while IFS= read -r class_file; do
    CLASS_FILES+=("$class_file")
  done < <(find "$CLASSES_DIR" -name '*.class' -print | sort)
  [[ "${#CLASS_FILES[@]}" -gt 0 ]] || die "no compiled Java classes found in $CLASSES_DIR"
fi

run "$D8" --lib "$ANDROID_JAR" --min-api 23 --output "$DEX_DIR" "${CLASS_FILES[@]}"
run zip -j "$UNSIGNED_APK" "$DEX_DIR/classes.dex"
run keytool -genkeypair -keystore "$KEYSTORE" -storepass android -keypass android -alias zmrdebug -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=ZMR Android Demo,O=ZMR,C=US"
run "$APKSIGNER" sign --ks "$KEYSTORE" --ks-key-alias zmrdebug --ks-pass pass:android --key-pass pass:android --out "$SIGNED_APK" "$UNSIGNED_APK"
if [[ -z "$ZMR_BIN" ]]; then
  if [[ -x "$ROOT/zig-out/bin/zmr" ]]; then
    ZMR_BIN="$ROOT/zig-out/bin/zmr"
  elif command -v zmr >/dev/null 2>&1; then
    ZMR_BIN="$(command -v zmr)"
  fi
fi

if [[ -n "$ZMR_BIN" ]]; then
  run "$ZMR_BIN" validate "$OUT/.zmr/android-smoke.json"
else
  echo "warning: skipped scenario validation because zmr was not found; run 'zmr validate $OUT/.zmr/android-smoke.json' after installation" >&2
fi

echo "created Android demo app at $OUT"
echo "apk: $SIGNED_APK"
echo "scenario: $OUT/.zmr/android-smoke.json"
