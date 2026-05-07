#!/usr/bin/env bash
set -euo pipefail

request="$(cat)"

case "$request" in
  *'"cmd":"snapshot"'*)
    cat <<'JSON'
{"status":"ok","nodes":[{"id":"continue-button","type":"android.widget.Button","label":"Continue","identifier":"continue_button","bounds":{"x":10,"y":20,"width":100,"height":44},"enabled":true,"visible":true,"selected":false}]}
JSON
    ;;
  *'"cmd":"tap"'*|*'"cmd":"type"'*|*'"cmd":"eraseText"'*|*'"cmd":"hideKeyboard"'*|*'"cmd":"swipe"'*|*'"cmd":"pressBack"'*|*'"cmd":"settle"'*)
    printf '{"status":"ok"}\n'
    ;;
  *)
    printf '{"status":"error","message":"unsupported command"}\n'
    exit 3
    ;;
esac
