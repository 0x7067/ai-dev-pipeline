# Output Style Rule

## Objective

Give every shell-stdout surface in this plugin (gate runners, orchestrator
banners, helper scripts) a consistent, capability-aware look — without
introducing a runtime dependency or letting ANSI escapes leak into committed
markdown.

## Source of Truth

`scripts/lib/style.sh` is the only allowed source of glyphs and colors.
Scripts MUST source it rather than re-implement banners.

```sh
# from a script under scripts/
source "${BASH_SOURCE%/*}/lib/style.sh"

# from a script under .claude/hooks/ or similar
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/style.sh"
```

The library is idempotent (`_STYLE_SH_LOADED` guard) and safe to source
under `set -euo pipefail`.

## Glyph Legend

| Unicode | ASCII fallback | Semantic       | Emitter           | Example                         |
|---------|----------------|----------------|-------------------|---------------------------------|
| `✓`     | `[ok]`         | success        | `style::ok`       | `✓ typecheck ok (3s)`           |
| `✗`     | `[fail]`       | failure        | `style::fail`     | `✗ lint failed rc=2 (1s)`       |
| `⏵`     | `-->`          | step / progress| `style::step`     | `⏵ running property tests`      |
| `●`     | `*`            | info           | `style::info`     | `● log: docs/aidp/runs/.../verify.log` |
| `●`     | `[warn]`       | warning        | `style::warn`     | `● skipped: no contract suite`  |
| `…`     | `...`          | de-emphasized  | `style::dim`      | `… elapsed 12s`                 |
| `↻`     | `[retry]`      | operation being retried | `style::retry` | `↻ lint retry 1/2`           |
| `↦`     | `->>`          | fan-in / aggregation result | `style::join` | `↦ read-only gates joined (rc=0,0,0)` |
| `─`     | `-`            | rule           | `style::rule`     | horizontal divider              |
| n/a     | n/a            | section header | `style::header`   | `== Verification gates ==`      |
| n/a     | n/a            | boxed message  | `style::box`      | framed callout                  |
| n/a     | n/a            | OSC-8 hyperlink | `style::hyperlink` | `style::hyperlink file:///abs/x.log x.log` |

Every glyph emitted by `scripts/lib/style.sh` MUST appear in this table
(invariant I5 of the standardization plan).

`style::hyperlink` does not introduce a printable glyph; it wraps the given
text in an OSC-8 escape sequence. It is gated by the readonly internal flag
`STYLE_HYPERLINKS`, derived ONCE at source-time as `STYLE_COLOR=1 AND
[ -t 1 ]`. There is NO new env var. When the flag is 0 (NO_COLOR,
CLICOLOR=0, or non-TTY stdout), the emitter prints the text only, with NO
escapes. `style::strip_ansi` strips OSC 8 in addition to CSI/SGR.

## Capability Environment Variables

Capabilities are parsed once at source-time into the readonly globals
`STYLE_COLOR`, `STYLE_UNICODE`, and `STYLE_USE_GUM`.

| Variable         | Effect                                                              |
|------------------|---------------------------------------------------------------------|
| `NO_COLOR`       | Any non-empty value disables color (per <https://no-color.org/>).   |
| `CLICOLOR=0`     | Disables color (per <https://bixense.com/clicolors/>).              |
| `CLICOLOR_FORCE=1` | Forces color even when stdout is not a TTY.                        |
| `LANG`/`LC_ALL`/`LC_CTYPE` | Match `*UTF-8*` (case-insensitive) → Unicode glyphs.        |
| `AIDP_USE_GUM`   | unset/empty=auto, `0`=force off, `1`=require `gum` (warn + fall back). |

Precedence for color: `NO_COLOR` > `CLICOLOR_FORCE=1` > `CLICOLOR=0` >
`isatty(stdout)`. Precedence for unicode: `LC_ALL` > `LC_CTYPE` > `LANG`.

## Boundary Parsing Note

Capability detection is the only boundary parser introduced by this rule.
Untrusted environment values are read once via `${VAR:-}` guards and
collapsed into two boolean flags (plus `STYLE_USE_GUM`) before any emitter
consumes them. Emitter functions never re-read raw env values; they only
branch on the typed flags. See `.claude/rules/boundary-parse-dont-validate.md`.

## FC/IS Placement

Output styling is **shell-only**. There is no core component:

- All emitters write to stdout/stderr (side effects).
- Core/business modules MUST NOT call `style::*`. Core returns plain
  domain values; the shell decides how to render them.
- Helper scripts (verifier, orchestrator wrappers) are shell, and may use
  the emitters freely.

See `.claude/rules/architecture-fcis.md`.

## Hard Rules

- **Never write ANSI escapes into committed `docs/*.md` files.** Either set
  `NO_COLOR=1` for the producing process, or pipe through
  `style::strip_ansi` before redirection.
- **Never re-implement glyphs locally.** If you need a new semantic glyph,
  add it to `scripts/lib/style.sh` and update this legend in the same
  change.
- **Never let optional `gum` rendering fail a gate.** The library already
  falls back to plain banners when `gum` is missing or returns non-zero.
- **Emitters must not alter `$?`.** They always `return 0`. Use them for
  presentation, not for flow control.

## Capability Test (Property)

```sh
unset LC_ALL LC_CTYPE
NO_COLOR=1 LANG=C bash -c '
  source scripts/lib/style.sh
  style::ok x; style::fail y; style::step z; style::header H
' | LC_ALL=C grep -P '[^\x00-\x7F]|\x1b'
# expected exit 1 (no matches)
```

## Reference

- `scripts/lib/style.sh`
- `.claude/rules/architecture-fcis.md`
- `.claude/rules/boundary-parse-dont-validate.md`
- `.claude/rules/release-and-verification.md`
- <https://no-color.org/>
- <https://bixense.com/clicolors/>
