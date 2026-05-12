# 02 — Backend

Patterns + scaffolds per backend stack. Load on backend tasks.

---

## Stack pick decision tree

```
Need heavy AI / async I/O / Python ecosystem?     → FastAPI
Need extreme throughput, single binary, ops simple? → Go + Gin
Already a Node-only team, want DI + structure?    → NestJS + Prisma
Want full admin UI + ORM for free?                → Django (DRF for API)
Edge runtime, minimal cold start?                 → Hono on Cloudflare Workers
Simple REST, prototype speed?                     → Express
```

When in doubt: **FastAPI** for AI-heavy, **Go + Gin** for everything else.

---

## FastAPI scaffold

```
apps/api/
├── pyproject.toml
├── alembic.ini
├── src/
│   ├── main.py                # FastAPI app factory
│   ├── core/
│   │   ├── config.py          # Pydantic Settings
│   │   ├── logging.py         # structlog
│   │   ├── security.py        # JWT, password hash
│   │   └── errors.py          # exception → response mapping
│   ├── db/
│   │   ├── base.py            # SQLAlchemy Base
│   │   ├── session.py         # async engine + session
│   │   └── models/
│   ├── domain/
│   │   ├── users/
│   │   │   ├── service.py
│   │   │   ├── repository.py
│   │   │   └── schemas.py
│   │   └── ...
│   ├── api/
│   │   ├── deps.py            # FastAPI dependencies
│   │   ├── v1/
│   │   │   ├── router.py
│   │   │   └── routes/
│   │   └── health.py
│   └── ai/                    # LLM router, prompts
└── tests/
```

### `main.py`

```python
from __future__ import annotations

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api.v1.router import api_v1
from .api.health import health_router
from .core.config import settings
from .core.logging import configure_logging
from .core.errors import install_exception_handlers


@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_logging()
    # init resources (DB pool, redis, LLM clients) here
    yield
    # graceful shutdown here


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version=settings.version,
        lifespan=lifespan,
        docs_url="/docs" if settings.env != "prod" else None,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(health_router)
    app.include_router(api_v1, prefix="/v1")
    install_exception_handlers(app)
    return app


app = create_app()
```

### `core/config.py`

```python
from __future__ import annotations

from functools import lru_cache
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "softco-api"
    version: str = "0.1.0"
    env: str = Field(default="dev", pattern="^(dev|staging|prod|test)$")

    database_url: str
    redis_url: str
    jwt_secret: str
    jwt_expire_minutes: int = 60

    anthropic_api_key: str | None = None
    openai_api_key: str | None = None

    cors_origins: list[str] = ["http://localhost:3000"]
    log_level: str = "INFO"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
```

### Async SQLAlchemy session

```python
# db/session.py
from __future__ import annotations

from collections.abc import AsyncIterator
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from ..core.config import settings

engine = create_async_engine(settings.database_url, pool_pre_ping=True, pool_size=10, max_overflow=20)
SessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
```

### Route + dep injection

```python
# api/v1/routes/users.py
from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from ....db.session import get_session
from ....domain.users.service import UserService
from ....domain.users.schemas import UserCreate, UserOut
from ...deps import current_user

router = APIRouter(prefix="/users", tags=["users"])


@router.post("", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def create_user(
    payload: UserCreate,
    session: AsyncSession = Depends(get_session),
) -> UserOut:
    return await UserService(session).create(payload)


@router.get("/me", response_model=UserOut)
async def me(user: UserOut = Depends(current_user)) -> UserOut:
    return user
```

### Errors

```python
# core/errors.py
from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse


class AppError(Exception):
    code = "INTERNAL"
    http_status = status.HTTP_500_INTERNAL_SERVER_ERROR

    def __init__(self, message: str, *, details: dict | None = None) -> None:
        self.message = message
        self.details = details or {}


class NotFound(AppError):
    code = "NOT_FOUND"
    http_status = status.HTTP_404_NOT_FOUND


class Conflict(AppError):
    code = "CONFLICT"
    http_status = status.HTTP_409_CONFLICT


def install_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _handle_app(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.http_status,
            content={"error": {"code": exc.code, "message": exc.message, "details": exc.details}},
        )
```

---

## Go + Gin scaffold

```
apps/api/
├── go.mod
├── cmd/api/main.go
├── internal/
│   ├── config/
│   ├── http/
│   │   ├── router.go
│   │   ├── middleware/
│   │   └── handlers/
│   ├── domain/
│   │   └── users/
│   │       ├── service.go
│   │       ├── repository.go
│   │       └── model.go
│   ├── db/
│   └── ai/
└── tests/
```

### `cmd/api/main.go`

```go
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"example.com/api/internal/config"
	"example.com/api/internal/http/router"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		slog.Error("config", "err", err)
		os.Exit(1)
	}

	r := router.New(cfg)
	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           r,
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server", "err", err)
			os.Exit(1)
		}
	}()
	<-ctx.Done()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
}
```

### Router + middleware

```go
// internal/http/router/router.go
package router

import (
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"example.com/api/internal/config"
	"example.com/api/internal/http/middleware"
)

func New(cfg *config.Config) *gin.Engine {
	if cfg.Env == "prod" {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.New()
	r.Use(gin.Recovery(), middleware.RequestID(), middleware.Logger(), cors.New(cors.Config{
		AllowOrigins: cfg.CORSOrigins, AllowCredentials: true,
	}))
	r.GET("/health", func(c *gin.Context) { c.JSON(200, gin.H{"status": "ok"}) })

	v1 := r.Group("/v1")
	registerUsers(v1)
	return r
}
```

### Handler + error envelope

```go
// internal/http/handlers/errors.go
package handlers

import "github.com/gin-gonic/gin"

type ErrEnvelope struct {
	Error struct {
		Code    string         `json:"code"`
		Message string         `json:"message"`
		Details map[string]any `json:"details,omitempty"`
	} `json:"error"`
}

func RespondErr(c *gin.Context, status int, code, msg string) {
	var e ErrEnvelope
	e.Error.Code = code
	e.Error.Message = msg
	c.AbortWithStatusJSON(status, e)
}
```

---

## NestJS scaffold (when Node is mandated)

```
apps/api/
├── src/
│   ├── main.ts
│   ├── app.module.ts
│   ├── common/
│   │   ├── filters/http-exception.filter.ts
│   │   ├── pipes/zod-validation.pipe.ts
│   │   └── decorators/current-user.decorator.ts
│   ├── modules/
│   │   ├── users/
│   │   │   ├── users.module.ts
│   │   │   ├── users.controller.ts
│   │   │   ├── users.service.ts
│   │   │   ├── users.repository.ts
│   │   │   └── dto/
│   │   └── auth/
│   └── prisma/prisma.service.ts
```

```ts
// main.ts
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import helmet from 'helmet';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  app.use(helmet());
  app.enableCors({ origin: process.env.CORS_ORIGINS?.split(',') ?? [], credentials: true });
  app.enableShutdownHooks();
  await app.listen(8000);
}
void bootstrap();
```

Use Zod-validation pipe (not `class-validator`) for runtime parity with shared
types.

---

## REST conventions (every stack)

| Aspect              | Rule                                                       |
| ------------------- | ---------------------------------------------------------- |
| Versioning          | URI prefix `/v1`, `/v2`                                    |
| Pagination          | Cursor-based: `?cursor=&limit=`                            |
| Filtering           | Explicit query params; no Mongo-style operators in URL     |
| IDs                 | UUID v7 (time-ordered) preferred                           |
| Timestamps          | ISO-8601 UTC                                               |
| Idempotency         | Mutations accept `Idempotency-Key` header                  |
| Errors              | `{ error: { code, message, details } }`                    |
| Rate limit          | `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `Retry-After`|
| Health              | `/health` (liveness), `/ready` (deps reachable)            |
| OpenAPI             | Auto-generated; served at `/docs` in non-prod              |

---

## Background jobs

| Language | Library    | Broker           |
| -------- | ---------- | ---------------- |
| Python   | Celery     | Redis / RabbitMQ |
| Python   | arq        | Redis            |
| Node     | BullMQ     | Redis            |
| Go       | asynq      | Redis            |

Rules:
- Idempotent jobs (deduplicate on `job_id`)
- Exponential backoff with jitter
- Dead-letter queue after N retries
- Timeouts on every job; no unbounded work
- Metrics: job duration, success/fail count

---

## Real-time

| Choice       | When                                                    |
| ------------ | ------------------------------------------------------- |
| SSE          | Server-push, no client-to-server real-time (LLM streaming) |
| WebSocket    | Bi-directional (chat, presence)                         |
| Pusher/Ably  | Multi-region, managed, fast to ship                     |
| Webhooks     | Out-of-band events to third parties (use HMAC signing)  |

WebSocket auth: query param `access_token` (short-lived) or first-message
auth; never long-lived secret in URL.

---

## Common pitfalls

- N+1 queries — every list endpoint must explicitly load relations
- Sync I/O in async handlers — `await` everything; CPU-bound work goes to
  worker / threadpool
- Untyped JSON in / out — validate at boundaries (Pydantic, Zod, structs +
  validator)
- Per-request DB engine — pool at app level, session per request
- Missing graceful shutdown — drain connections, finish in-flight requests
- Logs without correlation ID — every request gets a request-ID, propagated
  to downstream calls
