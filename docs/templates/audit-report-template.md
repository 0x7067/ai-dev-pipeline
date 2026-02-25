# [Project Name]: Holistic Audit Report

**Date:** YYYY-MM-DD
**Branch:** `branch-name`
**Auditor:** [Role or identifier]

## Executive Summary

[2-3 paragraphs covering: what the project is, what stack it uses, what stage it's at, what it does well, and what the most critical issues are. End with a clear statement about production readiness.]

---

## 1. Overall Structure and Conventions

### Project Layout

[Describe the repo structure. Monorepo or single app? What are the top-level directories and what do they contain?]

```
/
├── ...
```

**Severity: info**

[Commentary on whether the structure follows conventions and any deviations worth noting.]

### Backend Structure

[Describe the backend organization pattern. Module-per-feature? Layered? How are shared utilities organized?]

```
backend/
├── ...
```

**Severity: info**

### Frontend Structure

[Describe the frontend organization. App Router vs Pages? Component organization? State management approach?]

```
frontend/
├── ...
```

**Severity: info**

### Naming Conventions

**Severity: low | medium**

[Note any inconsistencies in naming: route prefixes, file naming, variable conventions, etc. Include specific locations.]

---

## 2. Critical or Urgent Issues

[Issues that must be fixed before production. Each finding follows this format:]

### 2.N [Short Title] [SEVERITY]

**Severity: critical | high**

[Description of the issue. What is happening, why it's a problem.]

[Code snippet if it helps illustrate the issue:]

```typescript
// file-path:line-range
code example
```

**Impact:** [What can go wrong. Be specific: data loss, unauthorized access, corruption, etc.]

**Location(s):**
- `/path/to/file.ts:line`
- `/path/to/other-file.ts:line`

**Recommendation:** [Concrete fix. Not vague advice, but what specifically to change.]

---

## 3. Improvement Suggestions (Non-Urgent)

[Issues that should be addressed but won't cause immediate harm. Same format as Section 2 but with medium/low severity.]

### 3.N [Short Title] [SEVERITY]

**Severity: medium | low**

[Description, impact, location, recommendation.]

---

## 4. Quick Wins

[Changes that can be made in under an hour each. Include time estimates.]

### 4.N [Short Title] [Time Estimate]

[What to do, where to do it, and why. Keep it actionable.]

**Location:** `/path/to/file.ts:line`

---

## 5. Meta-Level Observations

### Design Philosophy

[What approach does the team seem to follow? Product-driven? Infrastructure-first? What tradeoffs have they made, intentionally or not?]

### Inconsistencies Between Intent and Implementation

[Where does the codebase contradict itself? Examples: schema is production-grade but API layer isn't, auth model exists but isn't enforced, sophisticated client calls unprotected endpoints.]

### Technical Debt Assessment

[Categorize the debt by area and severity. Is the debt manageable? Will the architecture need a rewrite or just targeted fixes? What's the most expensive item to defer?]

---

## Appendix: Findings Summary Table

| # | Finding | Severity | Category |
|---|---------|----------|----------|
| 2.1 | ... | Critical | Security |
| 2.2 | ... | High | Architecture |
| ... | ... | ... | ... |

---

## Severity Definitions

- **Critical:** Must fix before any production deployment. Active security vulnerability or data integrity risk.
- **High:** Should fix before production. Significant risk or major quality gap.
- **Medium:** Address in the near term. Won't cause immediate harm but will compound over time.
- **Low:** Nice to fix. Minor inconsistency or improvement opportunity.
- **Info:** Observation only. No action required.
