#!/usr/bin/env bash
# Emit the static specs index page.
#
# Layer: shell. Discovery + write. Pure projection lives in
# scripts/specs/lib/spec-core.sh; parsing in scripts/specs/parse-spec.sh.
#
# This entry point is a thin convenience over render-html.sh for callers
# that only want the index regenerated. Implementation: re-run the full
# renderer (it is fast and idempotent — INV-4).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
exec bash "$SCRIPT_DIR/render-html.sh" "$@"
