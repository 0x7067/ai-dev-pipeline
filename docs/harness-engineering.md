# Harness Engineering Notes

This repository treats the verification harness as production code: it should be deterministic, diagnosable, and easy to run in local shells, CI, and copied consumer repositories.

## Practices Applied

- Run scripts from the repository root, regardless of the caller's current directory.
- Prefer explicit override environment variables over hidden auto-detection.
- Keep optional gates lenient by default, with strict `VERIFY_REQUIRE_*` switches for CI environments that need hard enforcement.
- Emit retry telemetry as JSON lines so downstream tools can parse failures without scraping prose logs.
- Prefer lockfile-aware package-manager detection over whichever binary happens to appear first in `PATH`.
- Keep GitHub Actions templates cache-neutral until the consuming repository's package manager and trust boundary are known.

## References

- GitHub Actions dependency caching guidance: https://docs.github.com/en/actions/concepts/workflows-and-actions/dependency-caching
- GitHub Actions dependency caching reference: https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching
- `actions/checkout` v6 runner and permission guidance: https://github.com/actions/checkout
- `actions/setup-node` v6 caching and security guidance: https://github.com/actions/setup-node
- ChromiumOS shell style guidance on Bash versus POSIX shell selection: https://www.chromium.org/chromium-os/developer-library/reference/style-guides/shell/
