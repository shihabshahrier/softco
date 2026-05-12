---
trigger: manual
---

When user wants to build, deploy, audit, or fix any software, follow `skill/SKILL.md`.

**Modes**: Greenfield | Audit | Extend | Fix | Infra-only | AI-add
**Phases**: Discovery (0) → Design (1) → Docs (2) → Code (3) → Test (4) → Infra (5) → Deploy (6)
**Critical**: docs before code; tests before impl; no hardcoded secrets; coverage ≥ 80%; user edits only .env
