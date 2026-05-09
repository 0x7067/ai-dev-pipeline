#!/usr/bin/env bash
# parse-manifest.sh — boundary parser for run-manifest/v1 JSON files.
#
# Layer: BOUNDARY. Per .claude/rules/boundary-parse-dont-validate.md, this
# is the single ingress point for any consumer that reads a manifest file.
# It parses the file into a stable line-oriented domain summary on stdout
# and rejects malformed input with a structured stderr error and exit 2.
#
# Usage:
#   bash scripts/parse-manifest.sh <path-to-manifest.json> [--run-dir <dir>]
#
# Acceptance contract (all must hold):
#   - top-level "schema" exactly equals "run-manifest/v1"
#   - required keys present: schema, run_id, command, status, artifacts
#   - run_id parses through scripts/parse-run-id.sh
#   - every artifacts[].path:
#       * is a non-empty string,
#       * contains no NUL byte,
#       * is not absolute (no leading "/"),
#       * contains no ".." segment,
#       * (when --run-dir is provided) realpath stays under run-dir.
#
# Exit codes:
#   0  accepted; stdout summary printed
#   2  rejected; stderr error printed
#   1  internal error (missing input, IO failure)
#
# Output (on accept), one field per line:
#   schema=<v>
#   run_id=<v>
#   command=<v>
#   status=<v>
#   artifact_count=<n>
#   artifact=<rel-path>
#   ... (one artifact= line per entry, in input order)
#
# Note: future v2 will surface its own bumped schema. v1 parser refuses
# anything other than "run-manifest/v1" — explicit per research §2.5.
# Manifest absence at the consumer (file does not exist) is NOT a parser
# error; consumers should treat that case as "no data yet" and never call
# this parser. We treat a missing argument file as exit 1 (internal).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/parse-run-id.sh
source "${SCRIPT_DIR}/parse-run-id.sh"

err() { printf 'parse-manifest: ERROR: %s\n' "$*" >&2; }

# Extract a top-level string value for <key> from JSON in $1.
# Tolerates spaces around colon. Returns 0 with value on stdout on success;
# returns 1 if not found.
#
# DEPTH-AWARE: only matches keys at brace depth 1 (i.e. direct children of
# the top-level object). Keys nested inside artifacts[] or any nested object
# are ignored. Required by .claude/rules/boundary-parse-dont-validate.md to
# prevent smuggled-key acceptance (review BLOCKING-1).
_extract_top_string() {
  local body="$1" key="$2"
  # Walk the body string-aware and brace-aware. Collect (key,value) string
  # pairs only when depth==1 and the next non-ws token after the key is ':'.
  local i=0 ch len=${#body}
  local depth=0 in_str=0 esc=0 tok="" cur_key=""
  local awaiting_colon=0 awaiting_value=0 reading_value=0
  while [ "$i" -lt "$len" ]; do
    ch=${body:i:1}
    if [ "$in_str" -eq 1 ]; then
      if [ "$esc" -eq 1 ]; then
        tok+="$ch"; esc=0
      elif [ "$ch" = "\\" ]; then
        tok+="$ch"; esc=1
      elif [ "$ch" = "\"" ]; then
        in_str=0
        # End of string token.
        if [ "$reading_value" -eq 1 ]; then
          # tok is the value bytes (raw, no surrounding quotes).
          if [ "$depth" -eq 1 ] && [ "$cur_key" = "$key" ]; then
            printf '%s' "$tok"
            return 0
          fi
          reading_value=0; cur_key=""; tok=""
        elif [ "$awaiting_value" -eq 0 ] && [ "$depth" -eq 1 ]; then
          # This was a key-position string at depth 1.
          cur_key="$tok"; tok=""; awaiting_colon=1
        else
          # String at depth>1, or a nested key — discard.
          tok=""
        fi
      else
        tok+="$ch"
      fi
    else
      case "$ch" in
        '"')
          in_str=1; tok=""
          if [ "$awaiting_value" -eq 1 ]; then
            reading_value=1; awaiting_value=0
          fi
          ;;
        '{')
          depth=$((depth+1))
          # New object resets key-tracking inside it.
          awaiting_colon=0; awaiting_value=0; cur_key=""
          ;;
        '}')
          depth=$((depth-1))
          awaiting_colon=0; awaiting_value=0; cur_key=""
          ;;
        '['|']')
          # Arrays don't change key context for top-level.
          if [ "$ch" = "[" ]; then depth=$((depth+1)); else depth=$((depth-1)); fi
          awaiting_colon=0; awaiting_value=0; cur_key=""
          ;;
        ':')
          if [ "$awaiting_colon" -eq 1 ]; then
            awaiting_colon=0; awaiting_value=1
          fi
          ;;
        ',')
          awaiting_colon=0; awaiting_value=0; cur_key=""
          ;;
        ' '|$'\t'|$'\n'|$'\r')
          : ;;
        *)
          # A non-string scalar (number, true/false/null) at value position —
          # not relevant for string extraction; just clear value-await.
          if [ "$awaiting_value" -eq 1 ]; then
            awaiting_value=0; cur_key=""
          fi
          ;;
      esac
    fi
    i=$((i+1))
  done
  return 1
}

# Extract the artifacts array body (between the outermost matching []).
# Returns 0 with array body (without surrounding brackets) on stdout, or
# 1 if not found.
_extract_artifacts_body() {
  local body="$1"
  # Locate the literal "artifacts" key.
  # shellcheck disable=SC2155
  local rest
  rest=${body#*\"artifacts\"}
  if [ "$rest" = "$body" ]; then
    return 1
  fi
  # rest now starts after "artifacts"; skip whitespace and colon.
  rest=${rest#*:}
  # Skip leading whitespace.
  rest=${rest##[[:space:]]}
  # Must start with [.
  case "$rest" in
    \[*) ;;
    *) return 1 ;;
  esac
  rest=${rest#\[}
  # Walk until matching ] at depth 0 (string-aware).
  local i=0 ch depth=1 in_str=0 esc=0 out=""
  local len=${#rest}
  while [ "$i" -lt "$len" ]; do
    ch=${rest:i:1}
    if [ "$in_str" -eq 1 ]; then
      out+="$ch"
      if [ "$esc" -eq 1 ]; then
        esc=0
      elif [ "$ch" = "\\" ]; then
        esc=1
      elif [ "$ch" = "\"" ]; then
        in_str=0
      fi
    else
      case "$ch" in
        '"') in_str=1; out+="$ch" ;;
        '[' ) depth=$((depth+1)); out+="$ch" ;;
        ']' ) depth=$((depth-1))
              if [ "$depth" -eq 0 ]; then
                printf '%s' "$out"
                return 0
              fi
              out+="$ch" ;;
        '{' ) depth=$((depth+1)); out+="$ch" ;;
        '}' ) depth=$((depth-1)); out+="$ch" ;;
        *)    out+="$ch" ;;
      esac
    fi
    i=$((i+1))
  done
  return 1
}

# Split top-level objects out of an array body. Each emitted line is one
# object's contents (without the surrounding {}). Brace-aware, string-aware.
_split_top_objects() {
  local s="$1"
  local i=0 ch depth=0 in_str=0 esc=0 buf=""
  local len=${#s}
  while [ "$i" -lt "$len" ]; do
    ch=${s:i:1}
    if [ "$in_str" -eq 1 ]; then
      buf+="$ch"
      if [ "$esc" -eq 1 ]; then esc=0
      elif [ "$ch" = "\\" ]; then esc=1
      elif [ "$ch" = "\"" ]; then in_str=0
      fi
    else
      case "$ch" in
        '"') in_str=1; buf+="$ch" ;;
        '{') if [ "$depth" -eq 0 ]; then buf=""; else buf+="$ch"; fi
             depth=$((depth+1)) ;;
        '}') depth=$((depth-1))
             if [ "$depth" -eq 0 ]; then
               printf '%s\n' "$buf"
               buf=""
             else
               buf+="$ch"
             fi ;;
        *) [ "$depth" -gt 0 ] && buf+="$ch" ;;
      esac
    fi
    i=$((i+1))
  done
}

# Containment check: is realpath(<run_dir>/<rel>) under realpath(<run_dir>)?
# Returns 0 if safe; 1 if escape detected.
_path_under_run_dir() {
  local run_dir="$1" rel="$2"
  local base abs
  base=$(cd "$run_dir" 2>/dev/null && pwd -P) || return 1
  # Resolve target without requiring it to exist: try cd if directory, else
  # parent + basename.
  local target="$run_dir/$rel"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -L "$target" ]; then
      # Follow symlink target. Prefer GNU/BSD `readlink -f`; fall back to
      # parent-cd + readlink for portability.
      if abs=$(readlink -f -- "$target" 2>/dev/null) && [ -n "$abs" ]; then
        :
      else
        local link_target pdir
        link_target=$(readlink -- "$target" 2>/dev/null) || return 1
        pdir=$(dirname -- "$target")
        case "$link_target" in
          /*) abs="$link_target" ;;
          *)  abs=$(cd "$pdir" 2>/dev/null && pwd -P)/"$link_target" ;;
        esac
      fi
    elif [ -d "$target" ]; then
      abs=$(cd "$target" 2>/dev/null && pwd -P) || return 1
    else
      local pdir bname
      pdir=$(dirname -- "$target")
      bname=$(basename -- "$target")
      abs=$(cd "$pdir" 2>/dev/null && pwd -P)/"$bname" || return 1
    fi
  else
    # Path does not exist: use logical parent walk. Reject any ".." that
    # would escape on dry-run by checking each segment relative to base.
    abs="$base/$rel"
  fi
  case "$abs" in
    "$base"|"$base"/*) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  local manifest_path="" run_dir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-dir) run_dir="$2"; shift 2 ;;
      --) shift; manifest_path="$1"; shift ;;
      -*) err "unknown flag: $1"; return 2 ;;
      *) if [ -z "$manifest_path" ]; then manifest_path="$1"; shift
         else err "extra positional arg: $1"; return 2; fi ;;
    esac
  done

  if [ -z "$manifest_path" ]; then
    err "missing path argument"
    return 1
  fi
  if [ ! -f "$manifest_path" ]; then
    err "manifest file not found: $manifest_path"
    return 1
  fi

  # Default run-dir to dirname(manifest_path) if not provided.
  if [ -z "$run_dir" ]; then
    run_dir=$(dirname -- "$manifest_path")
  fi

  # Read body. Reject embedded NUL bytes anywhere in the file.
  # Compare original byte count with NUL-stripped count; if they differ,
  # there is at least one NUL. This is portable across BSD/GNU.
  local body raw_bytes stripped_bytes
  raw_bytes=$(LC_ALL=C wc -c < "$manifest_path" 2>/dev/null | tr -d ' ')
  stripped_bytes=$(LC_ALL=C tr -d '\000' < "$manifest_path" 2>/dev/null | LC_ALL=C wc -c | tr -d ' ')
  if [ -n "$raw_bytes" ] && [ -n "$stripped_bytes" ] && [ "$raw_bytes" != "$stripped_bytes" ]; then
    err "NUL byte in manifest file"
    return 2
  fi
  body=$(cat -- "$manifest_path") || { err "read failed: $manifest_path"; return 1; }

  # --- required top-level fields ---
  local schema run_id command status
  schema=$(_extract_top_string "$body" "schema") || { err "missing required key: schema"; return 2; }
  run_id=$(_extract_top_string "$body" "run_id") || { err "missing required key: run_id"; return 2; }
  command=$(_extract_top_string "$body" "command") || { err "missing required key: command"; return 2; }
  status=$(_extract_top_string "$body" "status") || { err "missing required key: status"; return 2; }

  # Schema constancy.
  if [ "$schema" != "run-manifest/v1" ]; then
    err "unknown schema: $schema (expected run-manifest/v1)"
    return 2
  fi

  # RunId delegation.
  if ! parse_run_id "$run_id" >/dev/null 2>&1; then
    err "run_id failed parser: $run_id"
    return 2
  fi

  # --- artifacts array (required) ---
  local artifacts_body
  if ! artifacts_body=$(_extract_artifacts_body "$body"); then
    err "missing required key: artifacts (or malformed array)"
    return 2
  fi

  # --- emit accepted summary header ---
  printf 'schema=%s\n' "$schema"
  printf 'run_id=%s\n' "$run_id"
  printf 'command=%s\n' "$command"
  printf 'status=%s\n' "$status"

  # --- per-entry validation ---
  local count=0 obj path required_ok
  # Use a here-string to feed splitter through a while-read loop.
  local objects
  objects=$(_split_top_objects "$artifacts_body")
  if [ -n "$objects" ]; then
    while IFS= read -r obj; do
      [ -n "$obj" ] || continue
      # Required per-entry keys: kind, path, sha256, bytes.
      required_ok=1
      for k in kind path sha256 bytes; do
        if ! printf '%s' "$obj" | grep -qE "\"${k}\"[[:space:]]*:"; then
          required_ok=0
          err "artifact entry missing key: $k"
          break
        fi
      done
      [ "$required_ok" = "1" ] || return 2

      # Extract path.
      path=$(_extract_top_string "{$obj}" "path") || { err "artifact path unreadable"; return 2; }

      if [ -z "$path" ]; then
        err "artifact path empty"
        return 2
      fi
      # NUL bytes in the file are rejected at the file-content level above.
      # Bash cannot represent NUL inside a variable so a per-path check
      # is redundant here.
      # Absolute path.
      case "$path" in
        /*) err "artifact path is absolute: $path"; return 2 ;;
      esac
      # ".." segment (anywhere): reject lexically.
      case "/$path/" in
        */../*) err "artifact path contains '..': $path"; return 2 ;;
      esac
      # Backslash (Windows-style) — defensive.
      case "$path" in
        *\\*) err "artifact path contains backslash: $path"; return 2 ;;
      esac

      # Symlink-escape: realpath check against run_dir.
      if ! _path_under_run_dir "$run_dir" "$path"; then
        err "artifact path escapes run-dir: $path"
        return 2
      fi

      printf 'artifact=%s\n' "$path"
      count=$((count+1))
    done <<< "$objects"
  fi

  printf 'artifact_count=%d\n' "$count"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
  exit $?
fi
