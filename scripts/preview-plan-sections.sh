#!/usr/bin/env bash
# Boundary parser + shell wrapper: renders a bounded plan-preview block.
#
# Layer: shell (I/O wrapper). Pure parsing logic lives in the embedded
# python3/awk core invocation — it accepts raw Markdown as untrusted input
# and emits plain text only (no eval, no variable substitution).
#
# Contract (A1 / AC1–AC3, AC10, AC11, I2, I3, I5, I6, I7):
#   bash scripts/preview-plan-sections.sh <plan-path>
# Behavior:
#   - If <plan-path> does not exist or is empty → emit nothing (fail-closed).
#   - Else, attempt section-mode: find h2 headings matching each of the four
#     canonical names (Risk Tier, Risk rationale, Acceptance Criteria,
#     Boundary Map). If all four are located, emit each section under its
#     canonical heading.
#   - Else, emit a head-40-line fallback verbatim.
#   - In both modes, the output is hard-capped at 60 lines.
#   - ANSI escape sequences and ASCII control characters (except \n, \t)
#     are stripped before emission.
#   - Output is plain text — no shell substitution, no markdown rendering.

set -uo pipefail

PLAN_PATH="${1:-}"
HARD_CAP_LINES=60
HEAD_FALLBACK_N=40
SECTION_BODY_CAP=12   # per-section body line cap so 4 sections fit under 60

# Fail closed: missing/empty file → emit nothing.
if [ -z "$PLAN_PATH" ] || [ ! -f "$PLAN_PATH" ] || [ ! -s "$PLAN_PATH" ]; then
  exit 0
fi

# Hand the raw markdown to python3 for parsing. We pass the path as argv,
# never as a shell-expanded string, so embedded $() / backticks / ${VAR}
# tokens are inert text.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$PLAN_PATH" "$HARD_CAP_LINES" "$HEAD_FALLBACK_N" "$SECTION_BODY_CAP" <<'PYEOF'
import re
import sys

path = sys.argv[1]
hard_cap = int(sys.argv[2])
head_n = int(sys.argv[3])
body_cap = int(sys.argv[4])

# Canonical name → list of case-insensitive substring tokens that, if any
# appears inside the heading text, identify this section.
CANONICAL = [
    ("Risk Tier",          ["risk tier", "risk profile"]),
    ("Risk rationale",     ["risk rationale"]),
    ("Acceptance Criteria",["acceptance criteria"]),
    ("Boundary Map",       ["boundary map"]),
]

ANSI_RE = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')
# Defang shell-substitution-like substrings so adversarial agent-written
# Markdown cannot trick a downstream consumer into believing the preview
# was code-executed (R1 / I7). We only redact the *substitution payload*,
# not the surrounding prose, so the user can still tell something was
# scrubbed.
DOLLAR_PAREN_RE = re.compile(r'\$\([^)]*\)')
DOLLAR_BRACE_RE = re.compile(r'\$\{[^}]*\}')
BACKTICK_RE     = re.compile(r'`[^`]*`')

def sanitize(line: str) -> str:
    # Strip ANSI escapes.
    line = ANSI_RE.sub('', line)
    # Defang substitution-shaped tokens (plain-text only output, no inner
    # payload echoed — kills the PWNED / whoami / ${HOME} I7 corpus).
    line = DOLLAR_PAREN_RE.sub('$(...)', line)
    line = DOLLAR_BRACE_RE.sub('${...}', line)
    line = BACKTICK_RE.sub('`...`', line)
    # Strip ASCII control chars except TAB (\t = 0x09) and LF handled separately.
    line = ''.join(ch for ch in line if (ord(ch) >= 0x20 or ch == '\t'))
    return line

try:
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        raw_lines = f.read().splitlines()
except OSError:
    sys.exit(0)

# Find h2 headings (lines starting with "## ").
heading_idx = []  # list of (lineno, heading_text)
for i, ln in enumerate(raw_lines):
    if ln.startswith('## '):
        heading_idx.append((i, ln[3:].strip()))

# Try section mode: locate one heading per canonical name.
matched = {}  # canonical_name → (start_idx, heading_text)
for canon, tokens in CANONICAL:
    for idx, htext in heading_idx:
        if any(tok in htext.lower() for tok in tokens):
            if canon not in matched:
                matched[canon] = (idx, htext)
            break

section_mode = len(matched) == len(CANONICAL)

out_lines = []

def emit(line: str):
    if len(out_lines) >= hard_cap:
        return False
    out_lines.append(sanitize(line))
    return True

if section_mode:
    # For each canonical section in declaration order, emit "## <Canonical>"
    # followed by body lines until the next h2 heading, capped at body_cap.
    heading_lines = sorted(idx for idx, _ in heading_idx)
    for canon, _ in CANONICAL:
        start, _htext = matched[canon]
        # Find next heading after start.
        next_h = next((h for h in heading_lines if h > start), len(raw_lines))
        body = raw_lines[start + 1: next_h]
        # Trim leading/trailing blank lines from body for stable rendering.
        while body and not body[0].strip():
            body.pop(0)
        while body and not body[-1].strip():
            body.pop()
        if len(body) > body_cap:
            body = body[:body_cap] + ['…']
        if not emit(f"## {canon}"):
            break
        truncated = False
        for bl in body:
            if not emit(bl):
                truncated = True
                break
        if truncated:
            break
        # Blank separator between sections (only if room).
        if len(out_lines) < hard_cap:
            out_lines.append('')
else:
    # Head-N fallback: first head_n lines verbatim, capped at hard_cap.
    for ln in raw_lines[:head_n]:
        if not emit(ln):
            break

# Strip a trailing blank line if any (cosmetic, keeps idempotency clean).
while out_lines and out_lines[-1] == '':
    out_lines.pop()

# Final safety: strip any line beginning with `STATUS:` at column 0
# (I2 / AC10). We re-prefix with a single space to neutralize without
# losing information.
out_lines = [(' ' + ln) if ln.startswith('STATUS:') else ln for ln in out_lines]

# Hard cap one more time for paranoia.
out_lines = out_lines[:hard_cap]

sys.stdout.write('\n'.join(out_lines))
if out_lines:
    sys.stdout.write('\n')
PYEOF
fi
