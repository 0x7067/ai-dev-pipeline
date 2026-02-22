# Workflow Assessment Prompt Template (Claude-First, Reusable)

Use this template as a copy-paste prompt when assessing a Claude Code workflow.

```md
Assess the workflow in `${workflow_root}` using a Claude-first lens and produce a decision-complete improvement plan.

## Context
- Repository context: `${repo_context}`
- Workflow root: `${workflow_root}`
- Agent files glob: `${agent_files_glob}`
- Command files glob: `${command_files_glob}`
- Rule files glob: `${rules_files_glob}`
- Validation scripts: `${validation_scripts}`
- Risk profile: `${risk_profile}` (`low|medium|high`)
- Delivery mode: `${delivery_mode}` (`assessment_only|assessment_plus_plan`)

## Task
1. Evaluate current workflow quality for research, planning, implementation, and verification loops.
2. Assess agent-role separation, command orchestration, skill wiring, and hook/policy coverage.
3. Detect weak points in human-in-the-loop control points, evidence quality, and gating rigor.
4. Produce a target workflow with explicit loop controls for:
   - Research
   - Plan
   - Implement
   - Verify
5. If blocking findings exist, define retry loop policy with cap and remediation requirements.

## Constraints
- Evidence policy:
  - Official docs first (Claude Code + Anthropic engineering).
  - Allow up to 2 external sources only when official docs are insufficient.
  - Reject unsourced numeric performance claims.
- Keep recommendations generic and reusable across repositories.
- Explicitly separate:
  - Blocking findings
  - Advisory findings
- For `high` risk profile, require human approval gates before implementation and release.

## Output Format (Required Order)
1. **Evidence Summary**
2. **Current-State Assessment**
3. **Risk Register**
4. **Target Workflow (Research -> Plan -> Implement -> Verify)**
5. **Human-in-the-Loop Control Points**
6. **Implementation Backlog**
7. **Validation and Acceptance Tests**
8. **Assumptions and Open Questions**

## Scoring
Score each category from 0 to 5 using the rubric:
- Orchestration clarity
- Skill/subagent separation quality
- Human oversight quality
- Verification rigor
- Reusability/portability
```
