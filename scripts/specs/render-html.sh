#!/usr/bin/env bash
# Hand-rolled, single-file HTML renderer for docs/specs/.
#
# Layer: shell. Orchestrates the boundary parser (parse-spec.sh) and the
# pure core projections (lib/spec-core.sh), then writes static HTML to
# docs/specs/_site/.
#
# Determinism (INV-4): output is a pure function of the parsed Spec
# values. NO timestamps, NO host paths, NO env-derived strings.
#
# Usage:
#   bash scripts/specs/render-html.sh
#
# Exits non-zero if any spec fails to parse. All errors are surfaced;
# no partial-failure silence.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." >/dev/null 2>&1 && pwd -P)"

# shellcheck source=scripts/specs/lib/spec-core.sh
source "$SCRIPT_DIR/lib/spec-core.sh"

PARSER="$SCRIPT_DIR/parse-spec.sh"
SPECS_DIR="$REPO_ROOT/docs/specs"
SITE_DIR="$SPECS_DIR/_site"

if [[ ! -x "$PARSER" ]]; then
  echo "render-html: ERROR: parser not executable: $PARSER" >&2
  exit 2
fi

mkdir -p "$SITE_DIR"

# CSS: kept tiny + inline. No external assets, deterministic bytes.
read -r -d '' STYLE <<'EOF' || true
<style>
  :root { color-scheme: light dark; }
  body { font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
         max-width: 48rem; margin: 2rem auto; padding: 0 1rem;
         line-height: 1.5; }
  header h1 { margin-bottom: 0.25rem; }
  header .meta { color: #666; font-size: 0.9rem; }
  .tags { margin: 0.5rem 0 1rem 0; }
  .tag { display: inline-block; padding: 0 0.4rem; margin-right: 0.25rem;
         border: 1px solid currentColor; border-radius: 0.5rem;
         font-size: 0.8rem; }
  .risk-low { color: #2a7; }
  .risk-medium { color: #c80; }
  .risk-high { color: #c33; }
  .status { font-variant: small-caps; letter-spacing: 0.05em; }
  pre { background: rgba(127,127,127,0.1); padding: 0.5rem; overflow-x: auto; }
  table { border-collapse: collapse; }
  th, td { border-bottom: 1px solid rgba(127,127,127,0.3);
           padding: 0.25rem 0.5rem; text-align: left; }
  ul.specs { list-style: none; padding-left: 0; }
  ul.specs li { padding: 0.5rem 0; border-bottom: 1px solid rgba(127,127,127,0.2); }
  a { color: inherit; }
</style>
EOF

# render_spec_html <records> — egress serializer (Spec -> string).
# Pure with respect to records; emits HTML on stdout.
render_spec_html() {
  local records="$1"
  local id title status risk summary motivation scope
  id="$(spec_field "$records" id)"
  title="$(spec_field "$records" title)"
  status="$(spec_field "$records" status)"
  risk="$(spec_field "$records" risk)"
  summary="$(spec_field "$records" summary || true)"
  motivation="$(spec_field "$records" motivation || true)"
  scope="$(spec_field "$records" scope || true)"

  printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n'
  printf '<title>%s — Spec</title>\n' "$(html_escape "$title")"
  printf '%s\n' "$STYLE"
  printf '</head><body>\n'
  printf '<header>\n'
  printf '<p><a href="../index.html">&larr; all specs</a></p>\n'
  printf '<h1>%s</h1>\n' "$(html_escape "$title")"
  printf '<p class="meta">id: <code>%s</code> · status: <span class="status">%s</span> · risk: <span class="risk-%s">%s</span></p>\n' \
    "$(html_escape "$id")" "$(html_escape "$status")" "$(html_escape "$risk")" "$(html_escape "$risk")"

  printf '<p class="tags">'
  spec_list "$records" tags | while IFS='' read -r tag; do
    [[ -z "$tag" ]] && continue
    printf '<span class="tag">%s</span>' "$(html_escape "$(decode_value "$tag")")"
  done
  printf '</p>\n'
  printf '</header>\n'

  if [[ -n "$summary" ]]; then
    printf '<section><h2>Summary</h2><pre>%s</pre></section>\n' \
      "$(html_escape "$(decode_value "$summary")")"
  fi
  if [[ -n "$motivation" ]]; then
    printf '<section><h2>Motivation</h2><pre>%s</pre></section>\n' \
      "$(html_escape "$(decode_value "$motivation")")"
  fi
  if [[ -n "$scope" ]]; then
    printf '<section><h2>Scope</h2><pre>%s</pre></section>\n' \
      "$(html_escape "$(decode_value "$scope")")"
  fi

  _render_list_section "$records" acceptance_criteria "Acceptance Criteria"
  _render_list_section "$records" invariants "Invariants"
  _render_list_section "$records" boundary_map "Boundary Map"
  _render_list_section "$records" references "References"

  printf '</body></html>\n'
}

_render_list_section() {
  local records="$1" field="$2" heading="$3"
  local items
  items="$(spec_list "$records" "$field")"
  if [[ -z "$items" ]]; then
    return 0
  fi
  printf '<section><h2>%s</h2>\n<ol>\n' "$(html_escape "$heading")"
  printf '%s\n' "$items" | while IFS='' read -r item; do
    [[ -z "$item" ]] && continue
    printf '<li>%s</li>\n' "$(html_escape "$(decode_value "$item")")"
  done
  printf '</ol></section>\n'
}

# render_index_html <sorted-records-paths-file>
# Each line in the input file is the path to a typed-records file
# (parser output) for one spec. The renderer reads those records
# directly — it does NOT re-invoke the parser, satisfying the
# "parse each spec once per render" property.
render_index_html() {
  local sorted_records_paths_file="$1"
  printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n'
  printf '<title>Specs Index</title>\n'
  printf '%s\n' "$STYLE"
  printf '</head><body>\n'
  printf '<header><h1>Specs</h1>\n'
  printf '<p class="meta">Static index. Source of truth: <code>docs/specs/&lt;id&gt;/spec.yaml</code>.</p>\n'
  printf '</header>\n'
  printf '<ul class="specs">\n'
  while IFS='' read -r records_path; do
    [[ -z "$records_path" ]] && continue
    local records
    records="$(cat "$records_path")"
    local id title status risk
    id="$(spec_field "$records" id)"
    title="$(spec_field "$records" title)"
    status="$(spec_field "$records" status)"
    risk="$(spec_field "$records" risk)"
    printf '<li><a href="%s/index.html"><strong>%s</strong></a><br>' \
      "$(html_escape "$id")" "$(html_escape "$title")"
    printf '<span class="meta">status: <span class="status">%s</span> · risk: <span class="risk-%s">%s</span></span>' \
      "$(html_escape "$status")" "$(html_escape "$risk")" "$(html_escape "$risk")"
    printf '<div class="tags">'
    spec_list "$records" tags | while IFS='' read -r tag; do
      [[ -z "$tag" ]] && continue
      printf '<span class="tag">%s</span>' "$(html_escape "$(decode_value "$tag")")"
    done
    printf '</div></li>\n'
  done < "$sorted_records_paths_file"
  printf '</ul></body></html>\n'
}

main() {
  local errors=0
  local spec_yaml
  local -a all_paths=()
  # Collect every docs/specs/<id>/spec.yaml.
  while IFS='' read -r spec_yaml; do
    all_paths+=("$spec_yaml")
  done < <(find "$SPECS_DIR" -mindepth 2 -maxdepth 2 -name spec.yaml -type f -not -path "$SITE_DIR/*" | LC_ALL=C sort)

  # Explicit empty short-circuit. Avoids the need for the
  # `${arr[@]:-}` `set -u` workaround later on.
  if [[ ${#all_paths[@]} -eq 0 ]]; then
    echo "render-html: WARN: no specs found under $SPECS_DIR" >&2
    echo "render-html: OK ($SITE_DIR)"
    return 0
  fi

  # Process-scoped records dir. Each spec is parsed exactly once and
  # its typed records persist here for the index pass — never under
  # $SITE_DIR. Cleaned up on every exit path.
  local records_dir
  records_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$records_dir'" RETURN

  # Per-spec page. Parse once; capture records to sidecar; render.
  local p
  local -a records_files=()
  for p in "${all_paths[@]}"; do
    local records
    if ! records="$("$PARSER" "$p")"; then
      echo "render-html: ERROR: parse failed for $p" >&2
      errors=$((errors + 1))
      continue
    fi
    local id
    id="$(spec_field "$records" id)"
    local rec_file="$records_dir/$id.records"
    printf '%s\n' "$records" > "$rec_file"
    records_files+=("$rec_file")

    local out_dir="$SITE_DIR/$id"
    mkdir -p "$out_dir"
    local tmp="$out_dir/index.html.tmp"
    if ! render_spec_html "$records" > "$tmp"; then
      echo "render-html: ERROR: render failed for $p" >&2
      errors=$((errors + 1))
      rm -f "$tmp"
      continue
    fi
    mv "$tmp" "$out_dir/index.html"
  done

  # Sorted index. sort_specs reads each records file, extracts id,
  # and emits paths in id order — no parser re-invocation.
  local sorted_tmp
  sorted_tmp="$(mktemp)"
  sort_specs "${records_files[@]}" > "$sorted_tmp"

  local index_tmp="$SITE_DIR/index.html.tmp"
  if ! render_index_html "$sorted_tmp" > "$index_tmp"; then
    echo "render-html: ERROR: index render failed" >&2
    errors=$((errors + 1))
  else
    mv "$index_tmp" "$SITE_DIR/index.html"
  fi
  rm -f "$sorted_tmp"

  if [[ "$errors" -gt 0 ]]; then
    echo "render-html: FAILED with $errors error(s)" >&2
    return 1
  fi
  echo "render-html: OK ($SITE_DIR)"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
