# Code Style Rules

## Scope
Applies to all generated or modified code and scripts.

## Rules
- Prefer small, composable functions with explicit inputs and outputs.
- Avoid hidden global state and side effects in business logic.
- Name files and symbols by domain intent, not implementation detail.
- Keep comments concise and only for non-obvious logic.
- Avoid introducing dependencies unless there is clear project value.

## Portability Guidance
- Keep project-specific values configurable.
- Avoid hardcoded absolute paths.
- Prefer shell scripts with graceful tool detection for cross-project reuse.

## Language Examples

- Python: `@examples/python/anti_patterns.py`
- Go: `@examples/go/anti_patterns.go`
- Rust: `@examples/rust/anti_patterns.rs`
- TypeScript: `@examples/typescript/anti-patterns.ts`
