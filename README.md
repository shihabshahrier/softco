# softco

Autonomous software-company skill for AI coding agents. User describes a product;
SoftCo plans, documents, codes, tests, and deploys it. User only edits `.env`.

## What it is

An [Agent Skills](https://docs.claude.com/en/docs/claude-code/skills) skill
that turns any supported agent into a complete software firm — PM, architect, senior
engineer, DevOps, QA, security engineer, technical writer — operating under
a strict phase order:

```
Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6
Discovery  Design    Docs      Code      Test      Infra     Deploy
```

Documentation and tests come before code. Coverage ≥ 80% enforced. Secrets
never committed. Every project ships with an `AGENT.md` that lets a fresh
agent session continue the work without questions.

## Agent support

| Agent | Works | Install path |
|-------|-------|-------------|
| Claude Code | ✓ | `~/.claude/skills/softco` |
| opencode (SST) | ✓ | `~/.claude/skills/softco` (shared) |
| OpenAI Codex | ✓ | `~/.agents/skills/softco` |
| Amp / Goose / Kiro | ✓ | `~/.agents/skills/softco` (shared) |
| Gemini CLI | ✓ | `~/.gemini/antigravity/skills/softco` |
| Cursor | ✓ | `.cursor/rules/softco.mdc` (included) |
| Windsurf | ✓ | `.windsurf/rules/softco.md` (included) |
| Cline | ✓ | `.clinerules/softco.md` (included) |
| GitHub Copilot | ✓ | `.github/copilot-instructions.md` (included) |

## Install

```bash
./install.sh
```

Symlinks `skill/` to all detected agent paths. Restart your agent session to load.

Install for one agent only:

```bash
./install.sh --agent claude     # Claude Code + opencode
./install.sh --agent codex      # Codex / Amp / Goose / Kiro
./install.sh --agent gemini     # Gemini CLI
./install.sh --agent opencode   # opencode explicit path
./install.sh --agent openclaw   # OpenClaw
```

Uninstall from all:

```bash
./install.sh --uninstall
```

Copy files instead of symlinking (for sharing / distributing):

```bash
./install.sh --copy
```

## Manual install

```bash
# Claude Code
mkdir -p ~/.claude/skills && ln -s "$(pwd)/skill" ~/.claude/skills/softco

# Codex / Amp / Goose / Kiro
mkdir -p ~/.agents/skills && ln -s "$(pwd)/skill" ~/.agents/skills/softco

# Gemini CLI
mkdir -p ~/.gemini/antigravity/skills && ln -s "$(pwd)/skill" ~/.gemini/antigravity/skills/softco

# opencode
mkdir -p ~/.config/opencode/skills && ln -s "$(pwd)/skill" ~/.config/opencode/skills/softco
```

## Trigger phrases

The skill activates on requests like:

- "build me a SaaS / app / API / CLI"
- "design the architecture for ..."
- "set up CI/CD / Docker / Kubernetes / Terraform"
- "integrate Claude / GPT / Gemini / RAG / agent"
- "deploy to AWS / GCP / Azure / Fly / Render"
- "review / audit my repo"
- "fix this bug"

## Capabilities

- **Frontend**: React + Vite, Next.js, Vue, Svelte, React Native (Expo)
- **Backend**: FastAPI, Go + Gin, NestJS, Express, Hono, Django, Flask
- **AI**: Anthropic, OpenAI, Gemini, Bedrock, Vertex, Azure AI, Groq,
  Together, Ollama; LangChain / LangGraph / CrewAI / Haystack / MCP; RAG +
  agentic loops + structured output + prompt versioning
- **Databases**: Postgres + pgvector (default), MySQL, MongoDB, DynamoDB,
  Redis, Qdrant, Pinecone, Weaviate, Neo4j, OpenSearch
- **Infra**: Terraform-first; AWS, GCP, Azure, DigitalOcean, Fly, Render;
  Docker multi-stage; Kubernetes when justified
- **CI/CD**: GitHub Actions standard; templates for Python / Node / Go;
  OIDC auth; Trivy scan; release-please
- **Observability**: OpenTelemetry, structlog/pino/slog, Prometheus +
  Grafana, Sentry, Langfuse for LLM
- **Security**: OWASP defaults, OIDC for cloud, secrets manager injection,
  rate-limit, RLS multi-tenant, prompt-injection defence

## Layout

```
skill/                              # skill source (symlinked to agent paths)
├── SKILL.md                        # entry point loaded by all agents
├── references/
│   ├── 00-workflow.md              # phase-by-phase workflow
│   ├── 01-frontend.md
│   ├── 02-backend.md
│   ├── 03-ai-integration.md
│   ├── 04-databases.md
│   ├── 05-infrastructure.md
│   ├── 06-cicd.md
│   ├── 07-security.md
│   ├── 08-observability.md
│   ├── 09-testing.md
│   ├── 10-prompt-engineering.md
│   └── 11-doc-templates.md
├── scripts/
│   ├── scaffold.sh                 # bootstrap a project skeleton
│   ├── validate_env.py             # check .env matches .env.example
│   ├── gen_schema.py               # SQLAlchemy → docs/DB_SCHEMA.md
│   └── cost_estimate.py            # rough monthly cloud + LLM cost
└── assets/
    ├── github-actions-templates/   # ci-{python,node,go}.yml, deploy-ecs, terraform-plan, release-please
    ├── terraform-modules/          # network-aws, ecs-service-aws, rds-postgres-aws
    └── docker-templates/           # Dockerfile.{fastapi,go,nextjs,nestjs}, .dockerignore

# Agent adapters (Cursor/Windsurf/Cline/Copilot/Codex read these directly)
.cursor/rules/softco.mdc
.windsurf/rules/softco.md
.clinerules/softco.md
.codex/hooks.json
.github/copilot-instructions.md
agents/openai.yaml
AGENTS.md                           # Codex / Amp / Goose — @./skill/SKILL.md
GEMINI.md                           # Gemini CLI — @./skill/SKILL.md
```

## Usage

Inside any supported agent session:

```
> build me a small SaaS for tracking gym workouts, with AI workout suggestions
```

The agent detects intent, loads SoftCo, and starts at Phase 0. From there:
answer the interview, approve the TDR, watch docs land, watch modules land
test-first, and only ever edit `.env`.

For an existing repo:

```
> audit this repo and tell me what's missing for production readiness
```

For a focused task:

```
> add password reset to my FastAPI app
```

## What it never does

- Hardcodes secrets, even in examples
- `SELECT *` in production code
- Skips the documentation phase
- Pushes to `main` without CI passing
- Implements auth from scratch when a proven library exists
- Deploys without a health check
- Generates `.env` with real credentials (always `.env.example`)
- Uses `any` in production TypeScript

## License

MIT
