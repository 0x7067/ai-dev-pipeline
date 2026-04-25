#!/usr/bin/env bash
set -euo pipefail

HOOK_NAME="format-on-stop"
source "$(dirname "$0")/_hook_lib.sh"

if has_package_script "format"; then
  pkg_manager="$(detect_pkg_manager)"
  if [ -z "$pkg_manager" ]; then
    echo "format-on-stop: ERROR: package.json has format script but no supported package manager found"
    exit 1
  fi

  case "$pkg_manager" in
    bun)  run "$pkg_manager" run --silent format ;;
    npm)  run "$pkg_manager" run -s format ;;
    *)    run "$pkg_manager" run --silent format ;;
  esac
  exit $?
fi

echo "format-on-stop: skipped (no supported format command found)"
exit 0
