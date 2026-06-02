When user wants to build, deploy, audit, or fix any software, follow `skill/SKILL.md`.

**Modes**: Greenfield | Audit | Extend | Fix | Infra-only | AI-add
**Phases**: Discovery → Architecture → Design/UI (UI products) → Docs → Code → Test → Infra → Deploy

**Always**: recall AGENT.md + docs/PROGRESS.md first on existing repos; clear the verification gate — run the system and observe it working before claiming done (not just green tests); in fix mode declare the edit scope and avoid orthogonal edits.

**Never**: write code before docs exist (Phase 2); write impl before failing tests; hardcode secrets; skip CI health checks; use `SELECT *` in production; use `any` in TypeScript.
