# Boundary Rule: Parse, Don't Validate (Strict)

## Objective
All external data must be parsed into trusted domain types before use in core logic.

## Required Practice
- Parse at every ingress boundary: HTTP, CLI args, env vars, storage, queue messages, webhooks, user input.
- Parsing returns typed/trusted values or structured errors.
- Core modules only accept parsed domain values.

## Forbidden Practice
- Passing raw external payloads into core/domain logic.
- Scattered ad-hoc validation checks replacing boundary parsers.
- Treating unparsed data as trusted after boolean checks.

## Testing Requirements
- Parser accept/reject tests for boundary schemas.
- Round-trip parser/serializer tests where applicable.

## Reference
- https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/
