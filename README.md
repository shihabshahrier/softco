# SoftCo: a software company skill for AI coding agents

[![GitHub stars](https://img.shields.io/github/stars/shihabshahrier/softco.svg)](https://github.com/shihabshahrier/softco/stargazers)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Supported AI Agents](https://img.shields.io/badge/AI_Agents-Claude_Code_|_Cursor_|_Windsurf_|_Cline-blue.svg)](#agent-support)

SoftCo is an agent skill that makes an AI coding agent (Claude Code, Cursor, Windsurf, Cline and others) run a project the way a small software company would. You describe the product. The agent plans it, designs it, writes the documentation and the tests, then the code, the containers, the CI and the deployment. Your part is the `.env` file.

## What it is

An [Agent Skill](https://docs.claude.com/en/docs/claude-code/skills). It gives one agent seven roles to play in turn: product manager, architect, senior engineer, DevOps engineer, QA engineer, security reviewer and technical writer.

The work goes in a fixed order:

```
Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6
Discovery  Design    Docs      Code      Test      Infra     Deploy
```

Documentation and tests come before code. Test coverage must reach 80%. Secrets never go into git. Every project gets an `AGENT.md` file, so a fresh agent session can pick the work up without asking questions.

## Supported agents

SoftCo installs as a skill, a rules file or a system prompt, depending on the agent:

| Agent / Editor | Works | Install Path / Setup |
|-------|-------|-------------|
| **Claude Code** | ✓ | `~/.claude/skills/softco` |
| **opencode (SST)** | ✓ | `~/.claude/skills/softco` (shared) |
| **OpenAI Codex** | ✓ | `~/.agents/skills/softco` |
| **Amp / Goose / Kiro** | ✓ | `~/.agents/skills/softco` (shared) |
| **Gemini CLI** | ✓ | `~/.gemini/antigravity/skills/softco` |
| **Cursor** | ✓ | `.cursor/rules/softco.mdc` (included rules file) |
| **Windsurf** | ✓ | `.windsurf/rules/softco.md` (included rules file) |
| **Cline** | ✓ | `.clinerules/softco.md` (included custom rules) |
| **GitHub Copilot** | ✓ | `.github/copilot-instructions.md` (included instructions) |

## ⚙️ Installation & Setup

Easily install SoftCo across all detected AI agents on your local machine using the automated installer script:

```bash
./install.sh
```

This symlinks the `skill/` directory to all detected agent paths. Restart your agent session to load.

### Install for one specific agent only:

```bash
./install.sh --agent claude     # Claude Code + opencode
./install.sh --agent codex      # Codex / Amp / Goose / Kiro
./install.sh --agent gemini     # Gemini CLI
./install.sh --agent opencode   # opencode explicit path
./install.sh --agent openclaw   # OpenClaw
```

### Uninstall from all agents:

```bash
./install.sh --uninstall
```

### Copy files instead of symlinking (useful for distributing configurations):

```bash
./install.sh --copy
```

## 🛠️ Manual Installation

If you prefer manual configuration, run the appropriate setup commands for your AI toolchain:

```bash
# Claude Code Skill Setup
mkdir -p ~/.claude/skills && ln -s "$(pwd)/skill" ~/.claude/skills/softco

# Codex / Amp / Goose / Kiro Setup
mkdir -p ~/.agents/skills && ln -s "$(pwd)/skill" ~/.agents/skills/softco

# Gemini CLI / Antigravity Setup
mkdir -p ~/.gemini/antigravity/skills && ln -s "$(pwd)/skill" ~/.gemini/antigravity/skills/softco

# opencode Custom Skill Setup
mkdir -p ~/.config/opencode/skills && ln -s "$(pwd)/skill" ~/.config/opencode/skills/softco
```

## 🎯 Trigger Phrases & Intent Detection

SoftCo activates automatically within your agent workspace on natural language developer requests:

* **SaaS & API Greenfield Development**: `"build me a SaaS / web app / backend API / CLI tool"`
* **Architecture Planning**: `"design the architecture and system flow for ..."`
* **Infrastructure as Code (IaC) & DevOps**: `"set up CI/CD pipeline, Dockerfile, Kubernetes clusters, or Terraform modules"`
* **LLM & AI Agent Integration**: `"integrate Claude, OpenAI GPT, Gemini, RAG workflows, or MCP tools"`
* **Deployment & Orchestration**: `"deploy our application to AWS, GCP, Azure, Fly.io, or Render"`
* **Code Auditing & Security Review**: `"review my repository or audit my code for production readiness"`
* **Bug Fixing & Root-Cause Resolution**: `"fix this bug or resolve this specific runtime error"`

## ⚡ Core Capabilities & Supported Stack

SoftCo is pre-configured with industry-standard tech stack templates to accelerate development:

* **Frontend Frameworks**: React + Vite, Next.js (App Router), Vue, Svelte, React Native (Expo)
* **Backend Frameworks**: FastAPI (Python), Go + Gin, NestJS (Node), Express, Hono, Django, Flask
* **AI & LLM Integration**: Anthropic Claude, OpenAI GPT, Google Gemini, AWS Bedrock, GCP Vertex AI, Groq, Together AI, Ollama; LangChain, LangGraph, CrewAI, Haystack, Model Context Protocol (MCP); RAG + agentic loops + structured JSON outputs + prompt versioning
* **Databases & Vector Stores**: PostgreSQL + pgvector (default), MySQL, MongoDB, DynamoDB, Redis Cache, Qdrant, Pinecone, Weaviate, Neo4j, OpenSearch
* **Infrastructure (IaC)**: Terraform-first (modular architecture); AWS, GCP, Azure, DigitalOcean, Fly.io, Render; Docker multi-stage builds; Kubernetes orchestration
* **CI/CD Automation**: GitHub Actions standard workflows (Python / Node / Go templates); OIDC authentication; Trivy security vulnerability scanning; Release Please auto-changelogs
* **Observability & Logging**: OpenTelemetry instrumentation, structured JSON logging (structlog, pino, slog), Prometheus + Grafana metrics, Sentry error tracking, Langfuse for LLM evaluation
* **Security Standards**: OWASP Top 10 defaults, OIDC for cloud authentication, Secrets Manager integration, API Rate-Limiting, PostgreSQL RLS multi-tenancy, Prompt-Injection defenses

## 📂 Repository Architecture & File Layout

```
skill/                              # custom skill source directory (symlinked to agent paths)
├── SKILL.md                        # core entry point loaded by AI agents
├── references/                     # detailed technical guides
│   ├── 00-workflow.md              # phase-by-phase development workflow
│   ├── 01-frontend.md              # React/Next.js/SPA/SSR best practices
│   ├── 02-backend.md               # FastAPI/Go/Node API design patterns
│   ├── 03-ai-integration.md        # RAG, LLM orchestration & prompt engineering
│   ├── 04-databases.md             # SQL/NoSQL schema design & optimization
│   ├── 05-infrastructure.md        # AWS/GCP cloud setup with Terraform
│   ├── 06-cicd.md                  # GitHub Actions workflow pipelines
│   ├── 07-security.md              # OWASP compliance & secret management
│   ├── 08-observability.md         # OpenTelemetry, logging & APM metrics
│   ├── 09-testing.md               # Unit, integration, E2E, & AI testing
│   ├── 10-prompt-engineering.md    # Prompt optimization & version control
│   ├── 11-doc-templates.md         # Markdown document templates
│   ├── 12-verification.md          # Live-proof gate — run it & observe before "done"
│   └── 13-design.md                # UI direction, design tokens, component inventory
├── scripts/                        # helper automation scripts
│   ├── scaffold.sh                 # bootstraps standard project skeleton
│   ├── validate_env.py             # validates .env variables against .env.example
│   ├── gen_schema.py               # compiles SQLAlchemy models to DB_SCHEMA.md
│   └── cost_estimate.py            # calculates rough monthly cloud + LLM cost
└── assets/                         # pre-packaged templates
    ├── github-actions-templates/   # CI/CD pipelines (ci-python.yml, deploy-ecs, etc.)
    ├── terraform-modules/          # modular cloud infra (network, ECS, RDS)
    └── docker-templates/           # optimized multi-stage Dockerfiles
```

### Editor & Agent Adapters (Read directly by specific assistants)
* **Cursor rules**: `.cursor/rules/softco.mdc`
* **Windsurf rules**: `.windsurf/rules/softco.md`
* **Cline custom rules**: `.clinerules/softco.md`
* **OpenAI Codex hooks**: `.codex/hooks.json`
* **GitHub Copilot instructions**: `.github/copilot-instructions.md`
* **Agent configs**: `agents/openai.yaml`, [AGENTS.md](file:///Users/shahriar/Desktop/github/softco/AGENTS.md), [GEMINI.md](file:///Users/shahriar/Desktop/github/softco/GEMINI.md)

## 💡 Example Usage & Workflows

Run prompts like these inside any supported agent workspace session:

### Greenfield Project
```
> build me a small SaaS for tracking gym workouts, with AI workout suggestions
```
*The agent detects intent, loads the SoftCo skill, and starts at Phase 0 (Discovery). Answer the interactive questions, approve the TDR architecture plan, watch the documentation land, and review the test-driven code modules.*

### Repository Audit
```
> audit this repo and tell me what's missing for production readiness
```
*SoftCo parses the existing project, maps the architecture, and outputs a complete remediation plan (`docs/AUDIT.md`) scoring test coverage, security vulnerabilities, CI/CD pipelines, and documentation gaps.*

### Scoped Feature Extensions
```
> add password reset to my FastAPI app
```
*SoftCo updates `docs/MODULES.md` and related specs, writes failing tests first, implements the logic, verifies the tests pass, and details the changes in the changelog.*

## 🚫 Prohibited Actions & Strict Guardrails

SoftCo strictly adheres to enterprise-grade engineering principles and **never**:
* Hardcodes API keys, secrets, or passwords (always uses Secrets Manager or `.env.example`).
* Runs unoptimized or dangerous database queries (e.g., `SELECT *` in production schemas).
* Skips the documentation first phase (SDLC rigor is always enforced).
* Merges to the `main` branch without passing linting, formatting, and test suites.
* Implements authentication from scratch when proven libraries exist (Clerk, NextAuth, Supabase).
* Deploys services without active health check and readiness probe endpoints.
* Generates `.env` files with plaintext production credentials.
* Allows un-typed or dangerous types (like `any` in TypeScript) in production code.

## 📄 License

This project is licensed under the [MIT License](file:///Users/shahriar/Desktop/github/softco/LICENSE) — see the LICENSE file for details.

---

📖 **Project page:** https://shihub.site/projects/softco
