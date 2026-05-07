#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--version" ]]; then
  printf 'xcrun version 70\n'
  exit 0
fi

if [[ "${1:-}" != "simctl" ]]; then
  echo "expected simctl command: $*" >&2
  exit 2
fi
shift

case "${1:-}" in
  uninstall)
    if [[ "${2:-}" == "fake-ios-1" && "${3:-}" == "com.example.mobiletest" ]]; then
      echo "An error was encountered processing the command (domain=NSPOSIXErrorDomain, code=2):" >&2
      echo "No installed application with bundle identifier com.example.mobiletest" >&2
      exit 2
    fi
    echo "unsupported simctl uninstall command: $*" >&2
    exit 2
    ;;
  *)
    echo "unsupported simctl command: $*" >&2
    exit 2
    ;;
esac
