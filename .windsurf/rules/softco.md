---
trigger: manual
---

When user wants to build, deploy, audit, or fix any software, follow `skill/SKILL.md`.

**Modes**: Greenfield | Audit | Extend | Fix | Infra-only | AI-add
**Phases**: Discovery (0) → Architecture (1) → Design/UI (1.5) → Docs (2) → Code (3) → Test (4) → Infra (5) → Deploy (6)
**Critical**: recall AGENT.md + PROGRESS.md first on existing repos; docs before code; tests before impl; verification gate (run it and observe working, not just green tests); fix mode declares edit scope, no orthogonal edits; no hardcoded secrets; coverage ≥ 80%; user edits only .env
