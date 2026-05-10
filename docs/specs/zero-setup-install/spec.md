# Zero-Setup Install — Notes

## Two Install Modes

| Mode | Trigger | What it gives you | When to use |
|------|---------|-------------------|-------------|
| Zero-setup (default) | Plugin installed via marketplace; no further action | All commands, agents, skills, hooks, gate runner, templates resolve from `${CLAUDE_PLUGIN_ROOT}` | Interactive development. Trying out the pipeline. Solo work. |
| Vendored | Run `/setup` once | All scripts, rules, templates copied into the repo; `.github/workflows/verify.yml` optionally added | CI must run gates. Team wants artifacts checked into version control. Pin a snapshot. |

## Resolution Contract

```
harness_resolve_artifact P
  -> P                         if "$PWD/P" exists                    # repo-local precedence
  -> "$CLAUDE_PLUGIN_ROOT/P"   if that exists                         # plugin-root fallback
  -> exit 1, print searched=[...] to stderr  otherwise                # fail closed
```

Repo-local precedence is mandatory: vendored edits must always win over
plugin-shipped originals. The resolver is pure with respect to
`(PWD, CLAUDE_PLUGIN_ROOT, filesystem)` — no caching, no env-mutating
side effects.

## Boundary

`${CLAUDE_PLUGIN_ROOT}` is untrusted process-environment input. It is parsed
once per script:

```
harness_parse_plugin_root <env_value>
  -> PluginRoot(abs_path)   if non-empty AND is a directory AND contains .claude-plugin/plugin.json
  -> Unset                  if empty or unset (acceptable when running in vendored mode)
  -> Invalid                otherwise — abort with structured error
```

`harness_classify_install_mode` then folds the parsed root and a probe of
`scripts/run-verification-gates.sh`'s presence into one of
`Vendored | ZeroSetup | Broken`.

## Out of Scope (Future Work)

- `scripts/check-vendored-drift.sh` to warn when vendored copies diverge
  from plugin-shipped equivalents on plugin upgrade.
- Optional `bin/adp` entrypoint exposing `adp verify` / `adp gate <name>`.
- Auto-detection of stale vendored CI workflow when plugin upgrades the
  template.
