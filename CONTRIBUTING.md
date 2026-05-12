# Contributing

## Setup

```bash
git clone https://github.com/shihabshahrier/softco
cd softco
bash install.sh
```

## Making changes

1. Edit `skill/SKILL.md` or `skill/references/*.md`
2. Audit: run `/skill-builder --audit skill/SKILL.md` in a Claude Code session
3. Test: trigger the skill with at least two different prompts in a new session
4. Open a PR — describe what changed and why, with a before/after example

## Rules

- SKILL.md must pass skill-builder audit
- No secrets in any committed file
- Reference files >100 lines must have a `## Contents` TOC
- Keep SKILL.md under 5000 tokens — dense patterns belong in `skill/references/`
- Never add prose that belongs in a reference directly to SKILL.md

## File ownership

| File | Who edits |
|------|-----------|
| `skill/SKILL.md` | Anyone — this is the main behavior file |
| `skill/references/*.md` | Anyone — domain knowledge |
| `skill/scripts/` | Anyone — helper scripts |
| `skill/assets/` | Anyone — CI/Docker/Terraform templates |
| Agent adapters (`.cursor/`, etc.) | Derived from `skill/SKILL.md` — keep in sync |
