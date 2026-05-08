# Decoupling and Configuration Rules

## Objective
Keep modules independent of each other's internals and independent of environment-specific values, so a change in one place does not ripple through the codebase.

## Rules

### Tell, Don't Ask
- Functions should not pull data from an object to make a decision and then push the result back. Send the decision in.
- Read-only access for display or logging is fine. The rule targets *decisions*, not all reads.
- FC/IS caveat: in core, "tell, don't ask" maps to "compute the decision in core from explicit parameters; let shell apply it." Core does not reach back into shell-owned state.

### One Dot at a Time
- Avoid chaining method or property access across more than one level of abstraction your code does not own.
- `customer.findOrder(id).applyDiscount(d)` — each step is a domain operation, acceptable.
- `customer.orders.find(id).totals.grandTotal -= d` — exposes internal structure, not acceptable.
- Exception: stable libraries (stdlib, language built-ins) and pipelines on plain data (`xs.filter(...).map(...)`).

### No Global Mutable State
- No singletons-with-fields, no module-level mutables, no "config classes" with setters.
- External resources (DB, FS, HTTP client, time, RNG) count as global mutable state. Wrap them.
- If it is important enough to be global, wrap it in an API and inject the wrapper.

### Externalize What Changes
- No magic literals in core for: URLs, hostnames, ports, timeouts, retry counts, feature flags, file paths, secrets, credentials, environment names.
- Configuration is parsed at the boundary (per `boundary-parse-dont-validate.md`) into a typed `Config` value passed to core.
- Policy-shaped values (limits, thresholds, allowlists) are configuration, not code. Treat policy as metadata.

## Verification Hooks
- The `pragmatic-review-checklist` skill flags train wrecks, globals, and inlined config during `/review`.
- Static analysis (when configured) should reject module-level mutable state in core.

## Reference
- Thomas & Hunt, *The Pragmatic Programmer* (20th Anniversary Ed.), Tips 44-48, 55, 57, 79.
- See also `architecture-fcis.md`, `boundary-parse-dont-validate.md`.
