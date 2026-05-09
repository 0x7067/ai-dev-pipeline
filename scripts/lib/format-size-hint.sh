#!/usr/bin/env bash
# Pure formatter library: format_size_hint(n_lines) → "(N lines)".
#
# Layer: core (pure formatter). Sourced, not executed.
# Contract: AC8 / A4. Output shape MUST be exactly `(N lines)`.
# Invariant I2: output never starts with `STATUS:`.

format_size_hint() {
  # $1: integer line count. No validation here — boundary is the caller.
  printf '(%s lines)' "$1"
}
