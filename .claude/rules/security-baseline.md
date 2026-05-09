# Security Baseline Rules

## Objective
Prevent high-risk mistakes in generated workflows and code.

## Rules
- Never commit secrets, API keys, tokens, certificates, or private keys.
- Treat all external input as untrusted until parsed at boundaries.
- Avoid logging sensitive payloads.
- Enforce least-privilege tool and command usage.
- Fail closed on parser/authn/authz errors.

## Agent Tool Permissions: Allowlist-Only Convention

- Every agent definition file under `.claude/agents/*.md` MUST declare its
  permitted tools via an explicit `tools:` allowlist in the YAML frontmatter,
  and MUST NOT use a `disallowedTools:` field. This is the allowlist-only
  convention.
- Rationale (least-privilege, see Rules above): an explicit allowlist makes
  the permission surface obvious at a glance, eliminates the risk of a tool
  being implicitly permitted because nothing denied it, and prevents drift
  between two parallel fields. A tool absent from the allowlist is, by
  construction, not granted.
- Migration note: when removing a `disallowedTools:` line, the corresponding
  tools MUST also be absent from the `tools:` allowlist — the removal is a
  no-op only if the tool was never on the allowlist to begin with.
- Validator enforcement of this convention (failing the build when an agent
  file ships a `disallowedTools:` field) is tracked as future work.

## Sensitive Files (default)
- `.env*`
- `*.pem`, `*.key`, `*.p12`, `*.jks`, `*.keystore`
- lock files and package manager state files (project policy dependent)
