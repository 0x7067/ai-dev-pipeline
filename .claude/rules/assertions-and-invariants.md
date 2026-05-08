# Assertions and Invariants Rules

## Objective
Make impossible states actually impossible, and crash loudly when they happen anyway.

## Rules

### Design by Contract for Core
- Every core function declares (in code, comment, or test) its preconditions, postconditions, and any invariants it preserves.
- Preconditions are the caller's responsibility. Core does not silently sanitize bad inputs — that is the boundary's job.
- Postconditions are the function's promise and must be encoded in property tests where the property is non-trivial.

### Assert the Impossible
- When the code says "this can never happen," add an assertion that proves it cannot.
- Assertions encode invariants. They are not error handling — they are statements of fact that, if false, mean the program is corrupt and must stop.
- Do not catch and swallow assertion failures. Let them crash.

### Crash Early, Crash Loud
- On invariant violation, terminate the unit of work (request, job, transaction) immediately. Do not continue with corrupt state.
- Per `security-baseline.md`: fail closed. Per this rule: fail visible — log enough context to diagnose, then exit.
- "Catch-and-rethrow with logging" of every exception is an anti-pattern. Catch only what you can recover from; let the rest propagate.

### Finish What You Start
- The function or scope that allocates a resource is responsible for releasing it on every exit path, including failure.
- Use language idioms that guarantee release: `defer`, `using`, `with`, RAII, `try/finally`. Do not rely on the GC for files, sockets, locks, transactions.
- Long-running balanced resources (open in A, close in B) require an explicit ownership comment naming the closer.

## Verification Hooks
- Property tests assert postconditions and invariants (per `testing-formal-lite.md`).
- Contract tests assert boundary-layer pre/postconditions for parsed types.
- The `pragmatic-review-checklist` skill flags missing assertions on stated invariants and unmatched resource open/close pairs.

## Reference
- Thomas & Hunt, *The Pragmatic Programmer* (20th Anniversary Ed.), Tips 37-40.
- Meyer, *Object-Oriented Software Construction*, on Design by Contract.
- See also `testing-formal-lite.md`, `security-baseline.md`.
