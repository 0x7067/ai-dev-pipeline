# Workflow Assessment Rubric Template (0-5)

Use this rubric with `docs/templates/workflow-assessment-prompt-template.md`.

## Scale
- `0`: Missing or counterproductive
- `1`: Minimal, mostly ad hoc
- `2`: Partial and inconsistent
- `3`: Adequate baseline
- `4`: Strong and reliable
- `5`: Best-practice, reusable, and measurable

## Categories

### 1. Orchestration Clarity
- Definition: Phase ordering, transitions, and loop-control are explicit and deterministic.
- Checkpoints:
  - Commands and agents map cleanly.
  - Retry policy exists and is bounded.
  - Stop conditions are explicit.

### 2. Skill/Subagent Separation Quality
- Definition: Responsibilities are isolated with minimal overlap and clear contracts.
- Checkpoints:
  - Each agent has a distinct purpose.
  - Skill references are valid and intentional.
  - Deliverables are unambiguous.

### 3. Human Oversight Quality
- Definition: Human-in-the-loop controls are placed at high-impact decision points.
- Checkpoints:
  - Plan approval exists.
  - High-risk changes require explicit approval.
  - Release approval gate is present.

### 4. Verification Rigor
- Definition: Quality gates are deterministic, evidence-based, and severity-aware.
- Checkpoints:
  - Verification order is fixed.
  - Blocking vs advisory policy is explicit.
  - Evidence/citation quality requirements exist.

### 5. Reusability and Portability
- Definition: Workflow adapts to different repositories and toolchains with low coupling.
- Checkpoints:
  - Tool detection is dynamic.
  - Templates are parameterized.
  - Project-specific assumptions are minimized.

## Scorecard Template
| Category | Score (0-5) | Evidence | Gaps | Recommended Action |
|---|---:|---|---|---|
| Orchestration clarity |  |  |  |  |
| Skill/subagent separation quality |  |  |  |  |
| Human oversight quality |  |  |  |  |
| Verification rigor |  |  |  |  |
| Reusability/portability |  |  |  |  |

## Overall Rating
- Average score:
- Grade:
- Go/No-Go recommendation:
