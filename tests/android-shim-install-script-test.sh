#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

for args in "--app-root" "--test-package" "--runner" "--device" "--android-module" "--gradle-file"; do
  set +e
  missing_value_output="$("$ROOT/scripts/install-android-shim.sh" $args 2>&1)"
  missing_value_status=$?
  set -e
  if [[ "$missing_value_status" -ne 2 ]]; then
    echo "install-android-shim should exit 2 for missing value: $args" >&2
    exit 1
  fi
  grep -q -- "$args requires a value" <<< "$missing_value_output"
done

mkdir -p "$TMPDIR/app/android/app"
printf 'plugins { id "com.android.application" }\n' > "$TMPDIR/app/android/app/build.gradle"

"$ROOT/scripts/install-android-shim.sh" \
  --app-root "$TMPDIR/app" \
  --test-package com.example.mobiletest.test \
  --runner androidx.test.runner.AndroidJUnitRunner \
  --device emulator-5554 \
  --android-module android/app \
  --gradle-file android/app/build.gradle

test -x "$TMPDIR/app/.zmr/android-shim"
test -f "$TMPDIR/app/.zmr/ZMRShimInstrumentedTest.java"
test -f "$TMPDIR/app/android/app/src/androidTest/java/dev/zmr/shim/ZMRShimInstrumentedTest.java"

grep -q 'shell am instrument' "$TMPDIR/app/.zmr/android-shim"
grep -q 'ZMRShimInstrumentedTest' "$TMPDIR/app/.zmr/android-shim"
grep -q 'com.example.mobiletest.test/androidx.test.runner.AndroidJUnitRunner' "$TMPDIR/app/.zmr/android-shim"
grep -q 'UiDevice' "$TMPDIR/app/.zmr/ZMRShimInstrumentedTest.java"
grep -q 'testRunZMRCommand' "$TMPDIR/app/.zmr/ZMRShimInstrumentedTest.java"
grep -q 'UiDevice' "$TMPDIR/app/android/app/src/androidTest/java/dev/zmr/shim/ZMRShimInstrumentedTest.java"
grep -q 'BEGIN ZMR Android shim runner' "$TMPDIR/app/android/app/build.gradle"
grep -q 'testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"' "$TMPDIR/app/android/app/build.gradle"
grep -q 'BEGIN ZMR Android shim dependencies' "$TMPDIR/app/android/app/build.gradle"
grep -q 'androidTestImplementation "androidx.test:runner:' "$TMPDIR/app/android/app/build.gradle"
grep -q 'androidTestImplementation "androidx.test.uiautomator:uiautomator:' "$TMPDIR/app/android/app/build.gradle"

"$ROOT/scripts/install-android-shim.sh" \
  --app-root "$TMPDIR/app" \
  --test-package com.example.mobiletest.test \
  --android-module android/app \
  --gradle-file android/app/build.gradle >/dev/null

test "$(grep -c 'BEGIN ZMR Android shim dependencies' "$TMPDIR/app/android/app/build.gradle")" -eq 1
test "$(grep -c 'BEGIN ZMR Android shim runner' "$TMPDIR/app/android/app/build.gradle")" -eq 1

printf 'plugins { id("com.android.application") }\n' > "$TMPDIR/app/android/app/build.gradle.kts"
"$ROOT/scripts/install-android-shim.sh" \
  --app-root "$TMPDIR/app" \
  --test-package com.example.mobiletest.test \
  --runner androidx.test.runner.AndroidJUnitRunner \
  --android-module android/app \
  --gradle-file android/app/build.gradle.kts >/dev/null

grep -q 'BEGIN ZMR Android shim runner' "$TMPDIR/app/android/app/build.gradle.kts"
grep -q 'testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"' "$TMPDIR/app/android/app/build.gradle.kts"
grep -q 'androidTestImplementation("androidx.test:runner:' "$TMPDIR/app/android/app/build.gradle.kts"

mkdir -p "$TMPDIR/custom/android/app"
cat > "$TMPDIR/custom/android/app/build.gradle" <<'EOF'
plugins { id "com.android.application" }
android {
  defaultConfig {
    testInstrumentationRunner "com.example.CustomRunner"
  }
}
EOF
"$ROOT/scripts/install-android-shim.sh" \
  --app-root "$TMPDIR/custom" \
  --test-package com.example.mobiletest.test \
  --android-module android/app \
  --gradle-file android/app/build.gradle >/dev/null

grep -q 'com.example.mobiletest.test/com.example.CustomRunner' "$TMPDIR/custom/.zmr/android-shim"
test "$(grep -c 'BEGIN ZMR Android shim runner' "$TMPDIR/custom/android/app/build.gradle")" -eq 0
