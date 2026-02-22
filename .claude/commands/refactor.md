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

1. **Scope the refactoring.** Ask the user to confirm:
   - What to refactor (files, modules, patterns).
   - The structural goal (FC/IS alignment, extract boundary parsers, reduce duplication, improve naming, simplify control flow, etc.).
   - Confirm the behavioral equivalence constraint: no new features, no changed semantics.

2. **Assess test coverage for the refactoring target.** Before any structural changes, determine whether existing tests adequately cover the code being refactored:
   - Identify the public API surface, key code paths, and edge cases in the target code.
   - Check which of these are exercised by existing tests.
   - If coverage is sufficient, proceed to step 3.
   - If coverage is insufficient or no tests exist for the target code, proceed to step 2a.

   **2a. Generate characterization tests.** Run the `tester` agent to produce tests that capture the *current* behavior of the code being refactored:
   - Tests must describe what the code does today, not what it should do.
   - Cover the public API surface, return values, side effects, error cases, and edge cases of the target code.
   - These tests become the behavioral specification that the refactoring must preserve.
   - Characterization tests must pass before proceeding.

3. **Establish test baseline.** Run the full test suite (including any characterization tests from step 2a) to confirm a green baseline. If any tests fail, stop immediately — refactoring requires a passing test suite as the behavioral specification. Record the baseline result (pass count, suite name, command used).

4. **Run refactorer.** Execute the `refactorer` agent with the approved scope. The refactorer must:
   - Make only structural changes within the approved scope.
   - Preserve all existing tests and their assertions (including characterization tests).
   - Produce `docs/refactor-summary.md`.

5. **Run reviewer.** Execute the `reviewer` agent with an additional refactoring-specific lens:
   - Flag any change that alters observable behavior as **blocking**.
   - Flag any deleted or modified test assertion as **blocking**.
   - Flag any new functionality introduced as **blocking**.
   - Standard architecture/security/correctness lenses still apply.
   - If blocking findings exist, return to refactorer (max 2 loops).

6. **Verify behavioral equivalence.** Re-run the same test suite from step 3 with the same command. Compare results:
   - Same tests passing → equivalence confirmed.
   - New test failures → **blocking** — refactoring introduced a regression.
   - Fewer tests → **blocking** — tests were deleted without approval.
   - Record the comparison in `docs/refactor-summary.md`.

7. **Run verifier** with `medium` risk tier (per release-and-verification rules for non-trivial refactors). Enforce verification gates.

Stop immediately on unresolved blocking issues.
