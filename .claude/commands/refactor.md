---
description: Refactor code with behavioral equivalence guarantee and test-baseline verification.
agents:
  - tester
  - refactorer
  - reviewer
  - verifier
context: fork
---

Execute sequential refactoring phases:

1. **Establish test baseline.** Run the project's existing test suite to confirm a green baseline. If any tests fail, stop immediately — refactoring requires a passing test suite as the behavioral specification. Record the baseline result (pass count, suite name, command used).

2. **Scope the refactoring.** Ask the user to confirm:
   - What to refactor (files, modules, patterns).
   - The structural goal (FC/IS alignment, extract boundary parsers, reduce duplication, improve naming, simplify control flow, etc.).
   - Confirm the behavioral equivalence constraint: no new features, no changed semantics.

3. **Run refactorer.** Execute the `refactorer` agent with the approved scope. The refactorer must:
   - Make only structural changes within the approved scope.
   - Preserve all existing tests and their assertions.
   - Produce `docs/refactor-summary.md`.

4. **Run reviewer.** Execute the `reviewer` agent with an additional refactoring-specific lens:
   - Flag any change that alters observable behavior as **blocking**.
   - Flag any deleted or modified test assertion as **blocking**.
   - Flag any new functionality introduced as **blocking**.
   - Standard architecture/security/correctness lenses still apply.
   - If blocking findings exist, return to refactorer (max 2 loops).

5. **Verify behavioral equivalence.** Re-run the same test suite from step 1 with the same command. Compare results:
   - Same tests passing → equivalence confirmed.
   - New test failures → **blocking** — refactoring introduced a regression.
   - Fewer tests → **blocking** — tests were deleted without approval.
   - Record the comparison in `docs/refactor-summary.md`.

6. **Run verifier** with `medium` risk tier (per release-and-verification rules for non-trivial refactors). Enforce verification gates.

Stop immediately on unresolved blocking issues.
