#!/usr/bin/env bash
# Contract + property tests for scripts/specs/parse-spec.sh.
#
# Covers:
#  - Accept-set: each migrated spec.yaml under docs/specs/<id>/ parses.
#  - Reject-set: malformed inputs are rejected (unknown field, missing
#    required field, status whitelist, id<->path mismatch).
#  - Round-trip (INV-3): re-emit parser output as YAML and re-parse, the
#    second pass produces the same record set.
#  - id<->path invariant (INV-5).
#
# Self-contained: writes fixtures to a temp dir.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PARSER="$REPO_ROOT/scripts/specs/parse-spec.sh"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

if [[ ! -x "$PARSER" ]]; then
  fail "parser not executable: $PARSER"
  exit 1
fi

# --- Accept-set --------------------------------------------------------------
for spec in "$REPO_ROOT"/docs/specs/*/spec.yaml; do
  if "$PARSER" --check "$spec" >/dev/null 2>&1; then
    pass "accepts: ${spec#$REPO_ROOT/}"
  else
    fail "rejects valid: ${spec#$REPO_ROOT/}"
  fi
done

# --- Index parser -------------------------------------------------------------
if "$PARSER" --index "$REPO_ROOT/docs/specs/index.yaml" >/dev/null 2>&1; then
  pass "index parses"
else
  fail "index does not parse"
fi

# --- Reject-set --------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/missing-required"
cat > "$TMP/missing-required/spec.yaml" <<'EOF'
id: missing-required
title: Missing things
status: draft
risk: low
EOF
if "$PARSER" --check "$TMP/missing-required/spec.yaml" >/dev/null 2>&1; then
  fail "accepted spec with missing required fields"
else
  pass "rejects missing required fields"
fi

mkdir -p "$TMP/unknown-field"
cat > "$TMP/unknown-field/spec.yaml" <<'EOF'
id: unknown-field
title: x
status: draft
risk: low
summary: |
  s
motivation: |
  m
scope: |
  sc
acceptance_criteria: []
invariants: []
references: []
mystery_field: nope
EOF
if "$PARSER" --check "$TMP/unknown-field/spec.yaml" >/dev/null 2>&1; then
  fail "accepted unknown field"
else
  pass "rejects unknown field"
fi

mkdir -p "$TMP/bad-status"
cat > "$TMP/bad-status/spec.yaml" <<'EOF'
id: bad-status
title: x
status: WIP
risk: low
summary: |
  s
motivation: |
  m
scope: |
  sc
acceptance_criteria: []
invariants: []
references: []
EOF
if "$PARSER" --check "$TMP/bad-status/spec.yaml" >/dev/null 2>&1; then
  fail "accepted invalid status"
else
  pass "rejects invalid status"
fi

mkdir -p "$TMP/id-mismatch"
cat > "$TMP/id-mismatch/spec.yaml" <<'EOF'
id: not-id-mismatch
title: x
status: draft
risk: low
summary: |
  s
motivation: |
  m
scope: |
  sc
acceptance_criteria: []
invariants: []
references: []
EOF
if "$PARSER" --check "$TMP/id-mismatch/spec.yaml" >/dev/null 2>&1; then
  fail "accepted id-path mismatch (INV-5)"
else
  pass "rejects id-path mismatch (INV-5)"
fi

mkdir -p "$TMP/dup-field"
cat > "$TMP/dup-field/spec.yaml" <<'EOF'
id: dup-field
title: x
title: y
status: draft
risk: low
summary: |
  s
motivation: |
  m
scope: |
  sc
acceptance_criteria: []
invariants: []
references: []
EOF
if "$PARSER" --check "$TMP/dup-field/spec.yaml" >/dev/null 2>&1; then
  fail "accepted duplicate field"
else
  pass "rejects duplicate field"
fi

mkdir -p "$TMP/missing-boundary-map"
cat > "$TMP/missing-boundary-map/spec.yaml" <<'EOF'
id: missing-boundary-map
title: x
status: draft
risk: low
summary: |
  s
motivation: |
  m
scope: |
  sc
acceptance_criteria: []
invariants: []
references: []
EOF
if "$PARSER" --check "$TMP/missing-boundary-map/spec.yaml" >/dev/null 2>&1; then
  fail "accepted spec missing boundary_map"
else
  pass "rejects spec missing boundary_map"
fi

# --- Index reject-set: duplicate id ------------------------------------------
cat > "$TMP/dup-index.yaml" <<'EOF'
specs:
  - id: alpha
    title: Alpha
    status: draft
    risk: low
    tags: []
  - id: alpha
    title: Alpha Again
    status: draft
    risk: low
    tags: []
EOF
if "$PARSER" --index "$TMP/dup-index.yaml" >/dev/null 2>&1; then
  fail "accepted index with duplicate spec ids"
else
  pass "rejects index with duplicate spec ids"
fi

# --- Round-trip (INV-3) ------------------------------------------------------
# Strategy: parse a real spec, re-emit YAML from the records, re-parse,
# compare records. We use the simplest re-emit path possible because the
# accept set above already proves the parser handles the canonical shape.
roundtrip_one() {
  local src="$1"
  local id_dir; id_dir="$(basename "$(dirname "$src")")"
  # Mirror the source directory name so INV-5 (id<->path) holds for
  # the re-emitted file too.
  local tmp_root="$TMP/rt"
  mkdir -p "$tmp_root"
  local tmp_dir="$tmp_root/$id_dir"
  mkdir -p "$tmp_dir"
  local rec1
  if ! rec1="$("$PARSER" "$src")"; then
    fail "round-trip parse(src) failed: $id_dir"
    return 1
  fi

  # Re-emit canonical YAML from rec1.
  local out="$tmp_dir/spec.yaml"
  awk -F'\t' '
    function decode(s,   r) {
      r = s
      gsub(/\\\\/, "\x01", r)   # placeholder for literal backslash
      gsub(/\\n/, "\n", r)
      gsub(/\\t/, "\t", r)
      gsub(/\x01/, "\\", r)
      return r
    }
    BEGIN {
      scalar["id"] = scalar["title"] = scalar["status"] = scalar["risk"] = 1
      scalar["summary"] = scalar["motivation"] = scalar["scope"] = 1
      scalar["body_path"] = 1
      list["tags"] = list["acceptance_criteria"] = list["invariants"] = 1
      list["boundary_map"] = list["references"] = 1
    }
    {
      f = $1; v = decode($2)
      if (scalar[f]) {
        scalar_val[f] = v
        scalar_seen[f] = 1
      } else if (list[f]) {
        list_count[f]++
        list_val[f, list_count[f]] = v
      }
    }
    END {
      order_scalar[1]="id"; order_scalar[2]="title"; order_scalar[3]="status"; order_scalar[4]="risk"
      for (i=1; i<=4; i++) {
        f = order_scalar[i]
        printf "%s: %s\n", f, scalar_val[f]
      }
      # tags first (list)
      list_order[1]="tags"
      list_order[2]="acceptance_criteria"
      list_order[3]="invariants"
      list_order[4]="boundary_map"
      list_order[5]="references"
      # multi-line scalars
      ml[1]="summary"; ml[2]="motivation"; ml[3]="scope"
      for (i=1; i<=3; i++) {
        f = ml[i]
        if (!scalar_seen[f]) continue
        # Print with | block style
        printf "%s: |\n", f
        n = split(scalar_val[f], lines, "\n")
        for (j=1; j<=n; j++) {
          # Skip a trailing empty line that came from a final \n
          if (j == n && lines[j] == "") continue
          printf "  %s\n", lines[j]
        }
      }
      # tags (list - first)
      f = "tags"
      if (list_count[f] > 0) {
        printf "%s:\n", f
        for (j=1; j<=list_count[f]; j++) printf "  - %s\n", list_val[f, j]
      } else {
        printf "%s: []\n", f
      }
      # body_path scalar (optional)
      if (scalar_seen["body_path"]) {
        printf "body_path: %s\n", scalar_val["body_path"]
      }
      # remaining lists
      for (i=2; i<=5; i++) {
        f = list_order[i]
        if (list_count[f] > 0) {
          printf "%s:\n", f
          for (j=1; j<=list_count[f]; j++) printf "  - %s\n", list_val[f, j]
        } else {
          printf "%s: []\n", f
        }
      }
    }
  ' <<< "$rec1" > "$out"

  local rec2
  if ! rec2="$("$PARSER" "$out" 2>/dev/null)"; then
    fail "round-trip parse(reemit) failed: $id_dir"
    return 1
  fi
  # INV-3 compares typed values, not byte-wise field ordering. Compare
  # records as multisets keyed by (field, value). List items keep their
  # in-field order (using a stable counter); only top-level field order
  # is normalised.
  local norm1 norm2
  norm1="$(printf '%s\n' "$rec1" | awk -F'\t' '{c[$1]++; print $1 "\t" c[$1] "\t" $2}' | LC_ALL=C sort)"
  norm2="$(printf '%s\n' "$rec2" | awk -F'\t' '{c[$1]++; print $1 "\t" c[$1] "\t" $2}' | LC_ALL=C sort)"
  if [[ "$norm1" == "$norm2" ]]; then
    pass "round-trip: $id_dir"
  else
    fail "round-trip mismatch: $id_dir"
    diff <(printf '%s\n' "$norm1") <(printf '%s\n' "$norm2") | sed 's/^/    /' >&2 || true
  fi
}

for spec in "$REPO_ROOT"/docs/specs/*/spec.yaml; do
  roundtrip_one "$spec"
done

if [[ "$fail_count" -gt 0 ]]; then
  printf '\n%d assertion(s) failed\n' "$fail_count" >&2
  exit 1
fi
printf '\nall assertions passed\n'
