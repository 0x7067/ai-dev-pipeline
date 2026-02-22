# Security Baseline Rules

## Objective
Prevent high-risk mistakes in generated workflows and code.

## Rules
- Never commit secrets, API keys, tokens, certificates, or private keys.
- Treat all external input as untrusted until parsed at boundaries.
- Avoid logging sensitive payloads.
- Enforce least-privilege tool and command usage.
- Fail closed on parser/authn/authz errors.

## Sensitive Files (default)
- `.env*`
- `*.pem`, `*.key`, `*.p12`, `*.jks`, `*.keystore`
- lock files and package manager state files (project policy dependent)
