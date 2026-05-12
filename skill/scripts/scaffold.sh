#!/usr/bin/env bash
# scaffold.sh — bootstrap a SoftCo project structure from a TDR.
# Usage: scaffold.sh <project-name> --stack <fastapi-react|nextjs|gin-react|nestjs-react>
#
# Creates directory layout, baseline configs, Makefile, .env.example, .gitignore,
# docker-compose.yml, docs/ skeleton. Does NOT generate source code — that's
# Phase 3 work. Run from the directory where the new project should live.

set -euo pipefail

err() { printf '%s\n' "$*" >&2; exit 1; }
log() { printf '[scaffold] %s\n' "$*"; }

PROJECT=""
STACK="fastapi-react"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack) STACK="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
scaffold.sh <project-name> [--stack <fastapi-react|nextjs|gin-react|nestjs-react>]
USAGE
      exit 0 ;;
    -*) err "unknown flag: $1" ;;
    *) PROJECT="$1"; shift ;;
  esac
done

[[ -n "$PROJECT" ]] || err "project name required"
[[ ! -e "$PROJECT" ]] || err "$PROJECT already exists"

case "$STACK" in
  fastapi-react|nextjs|gin-react|nestjs-react) : ;;
  *) err "unknown stack: $STACK" ;;
esac

log "creating $PROJECT (stack: $STACK)"

mkdir -p "$PROJECT"
cd "$PROJECT"

mkdir -p docs infra/modules infra/environments/{dev,staging,prod} \
         .github/workflows .github/ISSUE_TEMPLATE

case "$STACK" in
  fastapi-react)
    mkdir -p apps/api/src/{core,db,domain,api/v1/routes,ai} \
             apps/api/tests/{unit,integration,e2e,ai/cases} \
             apps/web/src/{components,routes,lib,hooks,stores,styles} \
             packages/db/migrations/versions
    ;;
  nextjs)
    mkdir -p apps/web/app apps/web/components apps/web/lib \
             apps/api/src/{core,db,domain,api/v1/routes,ai} \
             apps/api/tests/{unit,integration,e2e,ai/cases} \
             packages/db/migrations/versions
    ;;
  gin-react)
    mkdir -p apps/api/cmd/api apps/api/internal/{config,http/{router,middleware,handlers},domain,db,ai} \
             apps/api/tests \
             apps/web/src/{components,routes,lib,hooks,stores,styles}
    ;;
  nestjs-react)
    mkdir -p apps/api/src/{common/{filters,pipes,decorators},modules,prisma} \
             apps/api/test \
             apps/web/src/{components,routes,lib,hooks,stores,styles}
    ;;
esac

cat > .gitignore <<'EOF'
# env
.env
.env.*
!.env.example

# python
__pycache__/
*.py[cod]
.venv/
.pytest_cache/
.mypy_cache/
.ruff_cache/
htmlcov/
.coverage
dist/
build/
*.egg-info/

# node
node_modules/
.next/
.turbo/
.nuxt/
.svelte-kit/
.pnpm-store/
coverage/

# go
bin/
*.test
*.out

# terraform
.terraform/
*.tfstate
*.tfstate.*
crash.log
override.tf
override.tf.json
*.auto.tfvars
*.auto.tfvars.json

# editor / OS
.DS_Store
.vscode/
.idea/
EOF

cat > .env.example <<'EOF'
# Copy to .env and fill values. See docs/ENV.md.
ENV=dev
LOG_LEVEL=INFO

DATABASE_URL=postgresql+asyncpg://app:dev@localhost:5432/app
REDIS_URL=redis://localhost:6379/0

JWT_SECRET=
JWT_EXPIRE_MINUTES=60

CORS_ORIGINS=http://localhost:3000

ANTHROPIC_API_KEY=
OPENAI_API_KEY=

SENTRY_DSN=
OTEL_EXPORTER_OTLP_ENDPOINT=
LANGFUSE_PUBLIC_KEY=
LANGFUSE_SECRET_KEY=
EOF

cat > Makefile <<'EOF'
.PHONY: setup dev test lint typecheck build deploy rollback clean

setup:
	@echo "Install deps. Override per stack."

dev:
	docker compose up --build

test:
	docker compose run --rm api pytest -q

lint:
	docker compose run --rm api ruff check .

typecheck:
	docker compose run --rm api mypy src

build:
	docker compose build

deploy:
	@echo "Use CI deploy job. Tag a release: git tag v0.X.Y && git push --tags"

rollback:
	@test -n "$$TO" || (echo "usage: make rollback ENV=prod TO=<sha>"; exit 1)
	@echo "Rolling back $$ENV to $$TO — implement via your deploy script"

clean:
	docker compose down -v
EOF

cat > docker-compose.yml <<'EOF'
services:
  db:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: dev
      POSTGRES_DB: app
    ports: ["5432:5432"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 5s
      timeout: 3s
      retries: 10
    volumes: ["db-data:/var/lib/postgresql/data"]

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

volumes:
  db-data: {}
EOF

for f in README AGENT ARCHITECTURE API DB_SCHEMA ENV INFRA MODULES TESTING CHANGELOG; do
  touch "docs/${f}.md"
done

cat > docs/CHANGELOG.md <<'EOF'
# Changelog

All notable changes to this project. Format: Keep a Changelog. SemVer.

## [Unreleased]

## [0.1.0] - $(date +%Y-%m-%d)
### Added
- Initial scaffold
EOF

cat > docs/PROGRESS.md <<'EOF'
# Progress

## Todo
- [ ] M1 — core config + logging
- [ ] M2 — DB schema + migrations
- [ ] M3 — auth

## In Progress
- [ ] (none)

## Done
- (none)
EOF

cat > .github/workflows/ci.yml <<'EOF'
# Replace with the template from softco/assets/github-actions-templates/ci.yml
# matching your stack. Placeholder so CI runs and reports a clean state.
name: ci
on:
  pull_request:
  push: { branches: [main] }
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo "scaffold pending — replace with the real workflow"
EOF

git init -q
git add -A
git commit -q -m "chore: initial scaffold

Co-Authored-By: SoftCo <noreply@anthropic.com>"

log "done — $PROJECT/"
log "next: 1) cp .env.example .env  2) fill values  3) make dev"
