#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  if [[ "$SOURCE" != /* ]]; then
    SOURCE="$SOURCE_DIR/$SOURCE"
  fi
done

ROOT="$(cd -P "$(dirname "$SOURCE")/.." && pwd)"
APP_ROOT=""
TEST_PACKAGE=""
RUNNER="androidx.test.runner.AndroidJUnitRunner"
RUNNER_PROVIDED=0
DEVICE=""
ANDROID_MODULE=""
GRADLE_FILE=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/install-android-shim.sh --app-root <dir> --test-package <id> [options]

Writes an app-local .zmr/android-shim command and Android instrumentation
source file.

Options:
  --app-root <dir>       App repository root. Required.
  --test-package <id>    Android test package, for example com.example.app.test. Required.
  --runner <class>       Instrumentation runner. Default: androidx.test.runner.AndroidJUnitRunner.
  --device <serial>      Optional adb device serial.
  --android-module <dir> Android app module dir, relative to app root or absolute.
                         Copies the shim into src/androidTest/java/dev/zmr/shim/.
  --gradle-file <file>   Gradle build file to patch with AndroidX test deps,
                         relative to app root or absolute. Guarded/idempotent.
  -h, --help             Show this help.

Without --android-module, add .zmr/ZMRShimInstrumentedTest.java to the app's
androidTest source set manually. With --android-module, this script writes the
source into the module's default androidTest tree.
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      APP_ROOT="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --test-package)
      TEST_PACKAGE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --runner)
      RUNNER="$(require_value "$1" "${2-}")"
      RUNNER_PROVIDED=1
      shift 2
      ;;
    --device)
      DEVICE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --android-module)
      ANDROID_MODULE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --gradle-file)
      GRADLE_FILE="$(require_value "$1" "${2-}")"
      shift 2
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

[[ -n "$APP_ROOT" ]] || die "--app-root is required"
[[ -n "$TEST_PACKAGE" ]] || die "--test-package is required"

mkdir -p "$APP_ROOT"
APP_ROOT="$(cd "$APP_ROOT" && pwd)"

app_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$APP_ROOT/$1" ;;
  esac
}

detect_gradle_runner() {
  local file="$1"
  local line=""
  local value=""
  line="$(grep -m1 'testInstrumentationRunner' "$file" || true)"
  [[ -n "$line" ]] || return 1
  value="$(printf '%s\n' "$line" | sed -E 's/.*testInstrumentationRunner[[:space:]]*(=)?[[:space:]]*"([^"]+)".*/\2/')"
  if [[ -n "$value" && "$value" != "$line" ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  return 1
}

patch_gradle_file() {
  local file="$1"
  [[ -f "$file" ]] || die "--gradle-file does not exist: $file"
  if ! grep -q 'testInstrumentationRunner' "$file" && ! grep -q 'BEGIN ZMR Android shim runner' "$file"; then
    if [[ "$file" == *.kts ]]; then
      cat >> "$file" <<EOF

// BEGIN ZMR Android shim runner
android {
    defaultConfig {
        testInstrumentationRunner = "$RUNNER"
    }
}
// END ZMR Android shim runner
EOF
    else
      cat >> "$file" <<EOF

// BEGIN ZMR Android shim runner
android {
    defaultConfig {
        testInstrumentationRunner "$RUNNER"
    }
}
// END ZMR Android shim runner
EOF
    fi
  fi

  if grep -q 'BEGIN ZMR Android shim dependencies' "$file"; then
    return
  fi

  if [[ "$file" == *.kts ]]; then
    cat >> "$file" <<'EOF'

// BEGIN ZMR Android shim dependencies
dependencies {
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}
// END ZMR Android shim dependencies
EOF
  else
    cat >> "$file" <<'EOF'

// BEGIN ZMR Android shim dependencies
dependencies {
    androidTestImplementation "androidx.test:runner:1.6.2"
    androidTestImplementation "androidx.test.ext:junit:1.2.1"
    androidTestImplementation "androidx.test.uiautomator:uiautomator:2.3.0"
}
// END ZMR Android shim dependencies
EOF
  fi
}

mkdir -p "$APP_ROOT/.zmr" "$APP_ROOT/.zmr/shims/android"
cp "$ROOT/shims/android/ZMRShimInstrumentedTest.java" "$APP_ROOT/.zmr/ZMRShimInstrumentedTest.java"

ANDROID_SOURCE_PATH=""
if [[ -n "$ANDROID_MODULE" ]]; then
  ANDROID_MODULE_PATH="$(app_path "$ANDROID_MODULE")"
  ANDROID_SOURCE_DIR="$ANDROID_MODULE_PATH/src/androidTest/java/dev/zmr/shim"
  ANDROID_SOURCE_PATH="$ANDROID_SOURCE_DIR/ZMRShimInstrumentedTest.java"
  mkdir -p "$ANDROID_SOURCE_DIR"
  cp "$ROOT/shims/android/ZMRShimInstrumentedTest.java" "$ANDROID_SOURCE_PATH"
fi

GRADLE_PATH=""
if [[ -n "$GRADLE_FILE" ]]; then
  GRADLE_PATH="$(app_path "$GRADLE_FILE")"
  if [[ "$RUNNER_PROVIDED" -eq 0 ]]; then
    DETECTED_RUNNER="$(detect_gradle_runner "$GRADLE_PATH" || true)"
    if [[ -n "$DETECTED_RUNNER" ]]; then
      RUNNER="$DETECTED_RUNNER"
    fi
  fi
  patch_gradle_file "$GRADLE_PATH"
fi

cat > "$APP_ROOT/.zmr/android-shim" <<EOF
#!/usr/bin/env bash
set -euo pipefail

ADB="\${ADB:-adb}"
DEVICE="$DEVICE"
adb_args=()
if [[ -n "\$DEVICE" ]]; then
  adb_args=(-s "\$DEVICE")
fi
REQUEST_LOCAL="\$(mktemp)"
RESPONSE_LOCAL="\$(mktemp)"
REQUEST_REMOTE="/data/local/tmp/zmr-request-\$\$.json"
RESPONSE_REMOTE="/data/local/tmp/zmr-response-\$\$.json"
trap 'rm -f "\$REQUEST_LOCAL" "\$RESPONSE_LOCAL"; "\$ADB" "\${adb_args[@]}" shell rm -f "\$REQUEST_REMOTE" "\$RESPONSE_REMOTE" >/dev/null 2>&1 || true' EXIT

cat > "\$REQUEST_LOCAL"

"\$ADB" "\${adb_args[@]}" push "\$REQUEST_LOCAL" "\$REQUEST_REMOTE" >/dev/null
"\$ADB" "\${adb_args[@]}" shell am instrument -w \\
  -e zmrRequestFile "\$REQUEST_REMOTE" \\
  -e zmrResponseFile "\$RESPONSE_REMOTE" \\
  -e class dev.zmr.shim.ZMRShimInstrumentedTest#testRunZMRCommand \\
  "$TEST_PACKAGE/$RUNNER" >/dev/null
"\$ADB" "\${adb_args[@]}" pull "\$RESPONSE_REMOTE" "\$RESPONSE_LOCAL" >/dev/null
cat "\$RESPONSE_LOCAL"
printf '\\n'
EOF

chmod +x "$APP_ROOT/.zmr/android-shim"

{
  echo "# ZMR Android Shim"
  echo ""
  echo "Generated for test package \`$TEST_PACKAGE\`."
  echo ""
  if [[ -n "$ANDROID_SOURCE_PATH" ]]; then
    echo "Installed instrumentation source:"
    echo ""
    echo "- \`${ANDROID_SOURCE_PATH#"$APP_ROOT"/}\`"
  else
    echo "Add \`.zmr/ZMRShimInstrumentedTest.java\` to the app's androidTest source set."
  fi
  echo ""
  echo "The androidTest target needs:"
  echo ""
  echo "- \`testInstrumentationRunner \"$RUNNER\"\`"
  echo "- \`androidx.test:runner\`"
  echo "- \`androidx.test.ext:junit\`"
  echo "- \`androidx.test.uiautomator:uiautomator\`"
  echo ""
  if [[ -n "$GRADLE_PATH" ]]; then
    echo "Patched Gradle runner/dependencies in:"
    echo ""
    echo "- \`${GRADLE_PATH#"$APP_ROOT"/}\`"
  else
    echo "Pass \`--gradle-file <module-build.gradle>\` to let this installer append a"
    echo "guarded dependency block for those libraries."
  fi
  echo ""
  echo "Run ZMR with:"
  echo ""
  echo "\`\`\`bash"
  echo "zmr run .zmr/android-smoke.json --android-shim ./.zmr/android-shim"
  echo "\`\`\`"
} > "$APP_ROOT/.zmr/android-shim.README.md"

echo "wrote $APP_ROOT/.zmr/android-shim"
echo "wrote $APP_ROOT/.zmr/ZMRShimInstrumentedTest.java"
if [[ -n "$ANDROID_SOURCE_PATH" ]]; then
  echo "wrote $ANDROID_SOURCE_PATH"
fi
if [[ -n "$GRADLE_PATH" ]]; then
  echo "patched $GRADLE_PATH"
fi
