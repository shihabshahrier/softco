When user wants to build, deploy, audit, or fix any software, follow `skill/SKILL.md`.

**Modes**: Greenfield | Audit | Extend | Fix | Infra-only | AI-add
**Phases**: Discovery → Architecture → Design/UI (UI products) → Docs → Code → Test → Infra → Deploy
**Rules**: recall AGENT.md + PROGRESS.md first on existing repos; docs before code; tests before implementation; verification gate — run it and observe it working before claiming done (not just green tests); fix mode declares edit scope, no orthogonal edits; never hardcode secrets; coverage ≥ 80%; user edits only .env
