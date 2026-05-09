#!/usr/bin/env bash
# Boundary parser + shell wrapper: emits up to 3 indented finding titles
# extracted from an agent-written report under a stable anchor heading.
#
# Layer: shell (I/O wrapper). Pure parsing logic lives in the embedded
# python3 invocation — input is treated as untrusted Markdown and never
# evaluated.
#
# Contract (A3 / AC5–AC7, AC10, AC11, I2, I4, I7):
#   bash scripts/preview-finding-titles.sh <report-path> <anchor-heading>
# Behavior:
#   - <anchor-heading> is the literal text of the report heading whose
#     bullet list we want, e.g. "## Blocking findings".
#   - Missing file → emit nothing (fail-closed).
#   - Missing anchor → emit nothing.
#   - Else, emit up to MAX_N (3) bullet titles, one per line, indented two
#     spaces. Titles longer than 120 chars are truncated with `…`.
#   - ANSI escapes and ASCII control chars are stripped; `$()`, `${...}`,
#     and backtick payloads are defanged before emission.

set -uo pipefail

REPORT_PATH="${1:-}"
ANCHOR="${2:-}"
MAX_N=3
TITLE_CAP=120

if [ -z "$REPORT_PATH" ] || [ -z "$ANCHOR" ] || [ ! -f "$REPORT_PATH" ] || [ ! -s "$REPORT_PATH" ]; then
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - "$REPORT_PATH" "$ANCHOR" "$MAX_N" "$TITLE_CAP" <<'PYEOF'
import re
import sys

path, anchor, max_n_s, cap_s = sys.argv[1:5]
max_n = int(max_n_s)
cap = int(cap_s)

ANSI_RE = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')
DOLLAR_PAREN_RE = re.compile(r'\$\([^)]*\)')
DOLLAR_BRACE_RE = re.compile(r'\$\{[^}]*\}')
BACKTICK_RE     = re.compile(r'`[^`]*`')

def sanitize(s: str) -> str:
    s = ANSI_RE.sub('', s)
    s = DOLLAR_PAREN_RE.sub('$(...)', s)
    s = DOLLAR_BRACE_RE.sub('${...}', s)
    s = BACKTICK_RE.sub('`...`', s)
    s = ''.join(ch for ch in s if (ord(ch) >= 0x20 or ch == '\t'))
    return s

try:
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.read().splitlines()
except OSError:
    sys.exit(0)

# Locate anchor heading.
# Matching is intentionally lenient so that orchestrator-side anchors
# (e.g. "## Blocking findings") match the actual template headings
# (e.g. "## Blocking Findings (Tool-Derived)" or
# "## 2. Critical or Urgent Issues"). We:
#   1. strip leading '#' chars and surrounding whitespace from both
#      the anchor and each candidate line
#   2. strip a leading numeric section prefix like "2." or "3) "
#   3. lowercase
#   4. require the candidate text to startswith the anchor text
HEADING_NUM_RE = re.compile(r'^\d+\s*[.\)]\s*')

def normalize_heading(s: str) -> str:
    s = s.lstrip()
    while s.startswith('#'):
        s = s[1:]
    s = s.strip()
    s = HEADING_NUM_RE.sub('', s)
    return s.lower()

anchor_norm = normalize_heading(anchor)
anchor_idx = None
for i, ln in enumerate(lines):
    if not ln.lstrip().startswith('#'):
        continue
    cand = normalize_heading(ln)
    if anchor_norm and cand.startswith(anchor_norm):
        anchor_idx = i
        break

if anchor_idx is None:
    sys.exit(0)

# Collect bullet titles after anchor until next heading or EOF.
titles = []
for ln in lines[anchor_idx + 1:]:
    stripped = ln.lstrip()
    # Stop at next markdown heading.
    if stripped.startswith('#'):
        break
    # First-level bullet: line starts with `- ` or `* ` after optional
    # leading whitespace, but with no leading spaces (top-level only).
    if ln.startswith('- ') or ln.startswith('* '):
        title = ln[2:].strip()
        if not title:
            continue
        # Title must be a single line (newlines already split).
        title = sanitize(title)
        if len(title) > cap:
            title = title[:cap] + '…'
        titles.append(title)
        if len(titles) >= max_n:
            break

INDENT = '  '
out = []
for t in titles[:max_n]:
    line = INDENT + t
    if line.startswith('STATUS:'):
        line = ' ' + line  # I2 / AC10 safety
    out.append(line)

sys.stdout.write('\n'.join(out))
if out:
    sys.stdout.write('\n')
PYEOF
fi
