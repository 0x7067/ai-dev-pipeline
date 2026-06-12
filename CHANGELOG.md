# Changelog

All notable changes to `ai-dev-pipeline` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-06-12

### Added

- Added `aidp-maintainer-improvement`, a bounded plugin skill for finding one small maintainer-reviewable improvement and stopping after one verified patch.
  Added a matching default plugin prompt.
- Added a thin Claude Code plugin manifest that reuses the same AIDP v2 skills without restoring the removed prompt, command, agent, or hook tree.

## [0.1.0] - 2026-06-12

### Added

- Introduced AIDP v2 as the only workflow surface: a Python CLI that writes typed run artifacts, compact worker packets, command evidence, and completion audits.
- Added the `aidp` console script with `doctor`, `plan`, `work`, `agent`, `check`, `prove`, `finish`, `self-test`, `cutover`, and Codex adapter commands.
- Added v2 artifact schemas under `docs/v2/`.
- Added the installable Codex plugin manifest at `.codex-plugin/plugin.json`.
- Added the `aidp-v2` Codex skill under `skills/aidp-v2/`.
- Added focused v2 tests under `tests/aidp/`.

### Removed

- Removed the previous prompt, shell, docs, examples, templates, workflow, and shell-test surfaces so v2 is the only maintained implementation.
