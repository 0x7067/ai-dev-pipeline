#!/usr/bin/env bash
# Unified preview helper.
#
# Layer: shell (I/O wrapper). Pure parsing logic lives in two python3 cores
# kept inline (plan-section parser, finding-title extractor). Both treat
# input as untrusted Markdown and emit plain text only.
#
# Usage:
#   bash scripts/preview.sh --anchor plan   <plan-path>
#   bash scripts/preview.sh --anchor review <report-path> --top <N> --heading <heading>
#   bash scripts/preview.sh --anchor verify <report-path> --top <N> --heading <heading>
#
# Anchors:
#   plan    → renders Risk/AC/Boundary section block (or head-40 fallback) from
#             ${PATH}; bounded at 60 lines.
#   review  → emits up to <top> bullet titles under <heading>.
#   verify  → emits up to <top> bullet titles under <heading>.
#
# Missing path / missing heading / empty file → emit nothing (fail-closed).

set -uo pipefail

ANCHOR=""
TOP=3
HEADING=""
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --anchor)  ANCHOR="${2:-}"; shift 2 ;;
    --top)     TOP="${2:-3}"; shift 2 ;;
    --heading) HEADING="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -*) echo "preview.sh: unknown flag: $1" >&2; exit 2 ;;
    *)  TARGET="$1"; shift ;;
  esac
done

if [ -z "$ANCHOR" ] || [ -z "$TARGET" ]; then
  echo "preview.sh: usage: --anchor <plan|review|verify> <path> [--top N --heading H]" >&2
  exit 2
fi

case "$ANCHOR" in
  plan)
    exec bash "$(dirname "$0")/preview-plan-sections.sh" "$TARGET"
    ;;
  review|verify)
    if [ -z "$HEADING" ]; then
      case "$ANCHOR" in
        review) HEADING="## Blocking findings" ;;
        verify) HEADING="## Gate Results" ;;
      esac
    fi
    # Delegate to the (legacy-named) finding-titles core. MAX_N is fixed at
    # 3 in that helper; --top is reserved for future use but currently only
    # forwarded as the script honors its internal cap.
    _ignored="$TOP"
    exec bash "$(dirname "$0")/preview-finding-titles.sh" "$TARGET" "$HEADING"
    ;;
  *)
    echo "preview.sh: unknown anchor: $ANCHOR (expected plan|review|verify)" >&2
    exit 2
    ;;
esac
