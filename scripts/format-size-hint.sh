#!/usr/bin/env bash
# Thin shell wrapper around scripts/lib/format-size-hint.sh.
# Usage: bash scripts/format-size-hint.sh <n>

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/format-size-hint.sh"

format_size_hint "${1:-0}"
