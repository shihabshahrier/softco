# 05 — Infrastructure

Terraform-first. No click-ops. Every cloud resource is code in `infra/`.

---

## Contents

- [Layout](#layout)
- [Backend + state](#backend--state)
- [Module pattern](#module-pattern)
- [Environment composition](#environment-composition)
- [Secrets](#secrets)
- [Cloud Run — GCP](#cloud-run-gcp-example)
- [Kubernetes — when to use](#kubernetes--use-when-scale-warrants)
- [Docker](#docker)
- [docker-compose for local dev](#docker-compose-for-local-dev)
- [Cost estimation](#cost-estimation)
- [Disaster recovery](#disaster-recovery)
- [Never do](#never-do)

---

## Layout

```
infra/
├── modules/
│   ├── network/        # VPC, subnets, NAT, IGW
│   ├── compute/        # ECS/Cloud Run/GKE service
│   ├── database/       # RDS / Cloud SQL
│   ├── cache/          # ElastiCache / Memorystore
│   ├── storage/        # S3 / GCS
│   ├── secrets/        # Secrets Manager / Secret Manager
│   ├── observability/  # CloudWatch / Grafana Cloud / Sentry
│   └── cdn/            # CloudFront / Cloud CDN
└── environments/
    ├── dev/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   ├── backend.tf
    │   └── terraform.tfvars
    ├── staging/
    └── prod/
```

Each environment composes modules with environment-specific vars. Never
duplicate module code across environments.

---

## Backend + state

S3 + DynamoDB lock (AWS):

```hcl
# environments/<env>/backend.tf
terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket         = "softco-tf-state"
    key            = "envs/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "softco-tf-lock"
    encrypt        = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}
```

GCS for GCP, Terraform Cloud for hosted state with policy gates.

State rules:
- One state file per environment, never shared
- Lock table enabled
- State versioning (S3 versioning) for recovery
- Secrets never in state? — impossible; treat state as a secret, encrypt at
  rest + restrict bucket ACL

---

## Module pattern

```hcl
# modules/compute/ecs-service/variables.tf
variable "name"            { type = string }
variable "cluster_arn"     { type = string }
variable "container_image" { type = string }
variable "container_port"  { type = number }
variable "cpu"             { type = number, default = 512 }
variable "memory"          { type = number, default = 1024 }
variable "desired_count"   { type = number, default = 2 }
variable "env_vars"        { type = map(string), default = {} }
variable "secret_arns"     { type = map(string), default = {} }
variable "subnet_ids"      { type = list(string) }
variable "security_group_ids" { type = list(string) }

# modules/compute/ecs-service/main.tf
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = var.name
    image     = var.container_image
    essential = true
    portMappings = [{ containerPort = var.container_port, hostPort = var.container_port }]
    environment = [for k, v in var.env_vars : { name = k, value = v }]
    secrets     = [for k, arn in var.secret_arns : { name = k, valueFrom = arn }]
    healthCheck = {
      command  = ["CMD-SHELL", "curl -fsS http://localhost:${var.container_port}/health || exit 1"]
      interval = 30
      timeout  = 5
      retries  = 3
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = var.name
      }
    }
  }])
}

# modules/compute/ecs-service/outputs.tf
output "service_arn"  { value = aws_ecs_service.this.id }
output "task_role_arn"{ value = aws_iam_role.task.arn }
```

Every variable has `description`. Every output documented.

---

## Environment composition

```hcl
# environments/prod/main.tf
locals {
  env  = "prod"
  tags = { Project = "softco", Env = local.env, ManagedBy = "terraform" }
}

module "network" {
  source = "../../modules/network"
  name   = "softco-${local.env}"
  cidr   = "10.10.0.0/16"
  azs    = ["us-east-1a", "us-east-1b", "us-east-1c"]
  tags   = local.tags
}

module "db" {
  source             = "../../modules/database/rds-postgres"
  name               = "softco-${local.env}"
  engine_version     = "16.4"
  instance_class     = "db.t4g.small"
  allocated_storage  = 100
  multi_az           = true
  backup_retention   = 14
  subnet_ids         = module.network.private_subnet_ids
  vpc_security_group_ids = [module.network.db_sg_id]
  tags               = local.tags
}

module "api" {
  source             = "../../modules/compute/ecs-service"
  name               = "softco-api-${local.env}"
  cluster_arn        = module.ecs_cluster.arn
  container_image    = "${var.ecr_repo}:${var.image_tag}"
  container_port     = 8000
  desired_count      = 3
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.network.app_sg_id]
  env_vars = {
    ENV       = local.env
    LOG_LEVEL = "INFO"
  }
  secret_arns = {
    DATABASE_URL       = module.db.connection_secret_arn
    JWT_SECRET         = aws_secretsmanager_secret.jwt.arn
    ANTHROPIC_API_KEY  = aws_secretsmanager_secret.anthropic.arn
  }
}
```

---

## Secrets

- AWS: Secrets Manager (rotated where possible)
- GCP: Secret Manager
- K8s: External Secrets Operator → cloud secrets manager
- Local: `.env` (gitignored), `.env.example` committed

Never:
- Secrets in `.tfvars`
- Secrets in environment variable defaults
- Secrets in Docker build args (leak in image history)
- Secrets in container env at build time (set at runtime)

---

## Cloud Run (GCP) example

```hcl
resource "google_cloud_run_v2_service" "api" {
  name     = "softco-api-${var.env}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.api.email
    scaling { min_instance_count = 1, max_instance_count = 10 }
    containers {
      image = var.container_image
      ports { container_port = 8000 }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_url.secret_id
            version = "latest"
          }
        }
      }
      resources { limits = { cpu = "1", memory = "1Gi" } }
      startup_probe   { http_get { path = "/ready" } }
      liveness_probe  { http_get { path = "/health" } }
    }
  }
}
```

---

## Kubernetes — use when scale warrants

Default to ECS Fargate / Cloud Run. Switch to K8s if any apply:

- Multi-cloud or hybrid
- Heavy stateful workloads
- Existing K8s ops team
- Per-pod GPU / specialised scheduling
- Helm-based vendor ecosystem requirements

When K8s: Helm chart per service, sealed-secrets or External Secrets,
HPA + KEDA for autoscaling, Istio / Linkerd only if a clear mesh need.

---

## Docker

### Multi-stage Dockerfile (FastAPI)

```dockerfile
# syntax=docker/dockerfile:1.7

FROM python:3.12-slim AS builder
ENV PIP_NO_CACHE_DIR=1 \
    POETRY_VIRTUALENVS_CREATE=false \
    PYTHONDONTWRITEBYTECODE=1
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml uv.lock ./
RUN pip install uv && uv sync --frozen --no-dev
COPY src/ ./src/

FROM python:3.12-slim AS runtime
ENV PYTHONUNBUFFERED=1 PORT=8000
RUN useradd -r -u 1001 -g root app
WORKDIR /app
COPY --from=builder /app /app
USER 1001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
```

### Multi-stage Dockerfile (Go)

```dockerfile
FROM golang:1.23 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/api ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/api /api
EXPOSE 8000
USER nonroot:nonroot
ENTRYPOINT ["/api"]
```

### Multi-stage Dockerfile (Next.js)

```dockerfile
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile

FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN corepack enable && pnpm build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup -g 1001 nodejs && adduser -S nextjs -u 1001
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]
```

Rules:
- Multi-stage always
- Non-root user
- No build tools in final image
- `HEALTHCHECK` defined
- `.dockerignore` excludes `.git`, `node_modules`, `.env*`, `dist`, `coverage`
- Pin base image tag (not `:latest`)
- Scan with Trivy in CI

---

## docker-compose for local dev

```yaml
services:
  api:
    build: ./apps/api
    env_file: .env
    ports: ["8000:8000"]
    depends_on:
      db: { condition: service_healthy }
      redis: { condition: service_started }

  web:
    build: ./apps/web
    env_file: .env
    ports: ["3000:3000"]
    depends_on: [api]

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
    volumes: ["db-data:/var/lib/postgresql/data"]

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

volumes:
  db-data:
```

---

## Cost estimation

For every TDR:

- Compute: vCPU × $/hr × hours × instances
- DB: instance + storage + I/O + backup storage
- LLM: tokens/user/day × cost/token × users
- Egress: GB out × $/GB
- Observability: log ingest GB + metrics + traces

`scripts/cost_estimate.py` produces a rough monthly figure from inputs. For
hard-budget projects, fetch official pricing URLs via WebFetch (AWS Calculator
API, GCP pricing).

---

## Disaster recovery

| Tier         | RPO    | RTO   | Strategy                           |
| ------------ | ------ | ----- | ---------------------------------- |
| Critical     | 5 min  | 1 hr  | Multi-AZ + PITR + cross-region replica |
| Important    | 1 hr   | 4 hr  | Multi-AZ + daily snapshot          |
| Best-effort  | 24 hr  | 24 hr | Daily snapshot                     |

Document in `INFRA.md`. Test restore at least quarterly.

---

## Never do

- `0.0.0.0/0` security group rules in prod
- Public S3 buckets (use CloudFront + OAC)
- IAM `*:*` policies
- Hardcoded AMI / image IDs without a data source
- Manual changes that drift from Terraform — recover with `terraform import`
  and remove the drift, never accept it
