# 06 — CI/CD

GitHub Actions default. Templates also in `assets/github-actions-templates/`.
Patterns identical for GitLab CI / CircleCI with translated syntax.

---

## Standard pipeline

```
trigger:
  pull_request → main
  push         → main
  tag          → v*.*.*

jobs:
  lint
  type-check
  test (unit + integration)
  build (docker image)
  scan (trivy)
  push (registry)
  deploy-dev   (on push to main)
  e2e          (against dev URL)
  deploy-prod  (on tag, with approval)
```

All jobs run on `pull_request` except `push`, `deploy-*`, `e2e`.

---

## Reusable workflow — full template

```yaml
# .github/workflows/ci.yml
name: ci

on:
  pull_request:
  push: { branches: [main], tags: ['v*'] }

permissions:
  contents: read
  id-token: write       # OIDC for cloud auth
  packages: write       # GHCR push
  pull-requests: write  # PR comments

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12', cache: 'pip' }
      - run: pip install uv && uv sync --frozen
      - run: uv run ruff check .
      - run: uv run ruff format --check .

  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12', cache: 'pip' }
      - run: pip install uv && uv sync --frozen
      - run: uv run mypy src tests

  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: pgvector/pgvector:pg16
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test
        ports: ['5432:5432']
        options: >-
          --health-cmd "pg_isready -U test"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10
      redis:
        image: redis:7-alpine
        ports: ['6379:6379']
    env:
      DATABASE_URL: postgresql+asyncpg://test:test@localhost:5432/test
      REDIS_URL: redis://localhost:6379/0
      JWT_SECRET: ci-test-secret-do-not-use-in-prod
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12', cache: 'pip' }
      - run: pip install uv && uv sync --frozen
      - run: uv run alembic upgrade head
      - run: uv run pytest --cov=src --cov-report=xml --cov-fail-under=80
      - uses: codecov/codecov-action@v4
        with: { files: coverage.xml, fail_ci_if_error: true }

  build:
    needs: [lint, typecheck, test]
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-latest
    outputs: { image: ${{ steps.meta.outputs.tags }} }
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}/api
          tags: |
            type=sha,prefix=sha-
            type=semver,pattern={{version}}
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}
      - uses: docker/build-push-action@v6
        with:
          context: ./apps/api
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: true
          sbom: true

  scan:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: aquasecurity/trivy-action@0.24.0
        with:
          image-ref: ${{ needs.build.outputs.image }}
          severity: 'CRITICAL,HIGH'
          exit-code: '1'
          ignore-unfixed: true

  deploy-dev:
    needs: [build, scan]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/gha-deploy-dev
          aws-region: us-east-1
      - run: |
          aws ecs update-service --cluster softco-dev --service api \
            --force-new-deployment --query 'service.serviceArn' --output text

  e2e:
    needs: deploy-dev
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'pnpm' }
      - run: pnpm install --frozen-lockfile
      - run: pnpm playwright install --with-deps
      - run: pnpm playwright test
        env: { BASE_URL: https://dev.example.com }
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: playwright-report, path: playwright-report }

  deploy-prod:
    needs: [build, scan]
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    environment:
      name: prod
      url: https://example.com
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID_PROD }}:role/gha-deploy-prod
          aws-region: us-east-1
      - run: |
          aws ecs update-service --cluster softco-prod --service api \
            --force-new-deployment
```

`environment: prod` triggers GitHub approval gate (configured per env in
repo Settings → Environments).

---

## Cloud auth — OIDC, never long-lived keys

### AWS

Create role + trust policy in Terraform:

```hcl
data "aws_iam_openid_connect_provider" "gh" {
  arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

resource "aws_iam_role" "gha_deploy" {
  name = "gha-deploy-${var.env}"
  assume_role_policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.gh.arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.org}/${var.repo}:environment:${var.env}" }
      }
    }]
  })
}
```

Scope `sub` claim by environment so dev role can't deploy to prod.

### GCP

Workload Identity Federation → Service Account impersonation.

### Azure

OIDC federated identity credentials on Service Principal.

---

## Branch protection (required)

- `main` requires PR
- All status checks pass
- 1+ reviewer approval (Codeowners for sensitive paths)
- Signed commits (optional but recommended)
- Linear history (squash merge)
- No force push

Configure as code via `github-codeowners` + Terraform `github_branch_protection`
(or repository settings).

---

## CODEOWNERS

```
# .github/CODEOWNERS
*                       @<team>/dev
apps/api/auth/**        @<team>/security
infra/**                @<team>/devops
packages/ai/**          @<team>/ai
docs/**                 @<team>/dev
.github/workflows/**    @<team>/devops
```

---

## Release workflow

```yaml
# .github/workflows/release.yml
name: release
on:
  push:
    branches: [main]
permissions:
  contents: write
  pull-requests: write
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          release-type: simple
          package-name: softco
```

Conventional Commits → automatic CHANGELOG + version bump + tag. Tag triggers
`deploy-prod`.

---

## Dependabot

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: pip
    directory: /apps/api
    schedule: { interval: weekly }
    groups: { python: { patterns: ['*'] } }
  - package-ecosystem: npm
    directory: /apps/web
    schedule: { interval: weekly }
  - package-ecosystem: docker
    directory: /apps/api
    schedule: { interval: weekly }
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
  - package-ecosystem: terraform
    directory: /infra
    schedule: { interval: weekly }
```

---

## PR previews (frontend)

- Vercel: enabled per project, automatic
- Self-hosted: ephemeral Cloud Run / ECS service per PR, torn down on close

---

## Rollback

- App: re-tag previous image SHA in ECS / Cloud Run → automatic rollout
- Infra: `terraform apply` of previous version, or `terraform state rm` +
  re-import
- DB migration: forward-only; if irreversible, restore from PITR snapshot

`make rollback ENV=prod TO=<sha>` documents the standard command.

---

## Pre-commit hooks (mirror CI locally)

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9
    hooks:
      - id: ruff
      - id: ruff-format
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.11.2
    hooks: [{ id: mypy }]
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks: [{ id: gitleaks }]
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-yaml
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: detect-private-key
```

---

## Never do

- Long-lived cloud access keys in secrets
- Bypassing branch protection
- `latest` Docker tag in prod
- Manual deploy from a developer machine
- Skipping the security scan job
- Deploying without health-check gate
- Storing test secrets in plaintext repo files (use `vars` / `secrets`)
