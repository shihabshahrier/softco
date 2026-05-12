# CLAUDE.md — softco

## What this repo is

softco is an agent skill for AI coding agents. It acts as a complete software company — PM, architect, senior engineer, DevOps, QA, and tech writer — so the user only has to describe what they want built.

## Source of truth — edit only these

| File | Controls |
|------|----------|
| `skill/SKILL.md` | All skill behavior and phase rules |
| `skill/references/*.md` | Domain knowledge, loaded lazily per phase |
| `skill/scripts/` | Helper scripts (scaffold, validate_env, gen_schema, cost_estimate) |
| `skill/assets/` | CI templates, Dockerfiles, Terraform modules |

## Agent-specific files (sync from source, don't edit directly)

`.cursor/rules/softco.mdc` · `.windsurf/rules/softco.md` · `.clinerules/softco.md`
`.codex/` · `.github/copilot-instructions.md` · `agents/openai.yaml`
`AGENTS.md` · `GEMINI.md` · `gemini-extension.json`

These are condensed adapters derived from `skill/SKILL.md`. If behavior needs to change, edit the source first.

## Key constraints

- `skill/SKILL.md` must stay under 5000 tokens
- Reference files >100 lines need a `## Contents` TOC at the top
- Never hardcode secrets, even in examples
- Run `/skill-builder --audit skill/SKILL.md` after any SKILL.md change

## Making changes

1. Edit `skill/SKILL.md` or `skill/references/*.md`
2. Run `/skill-builder --audit skill/SKILL.md` to check compliance
3. Run `bash install.sh` to re-sync symlinks
4. Test in a new agent session
5. Open a PR with a before/after example
