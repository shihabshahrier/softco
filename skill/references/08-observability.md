# 08 — Observability

Three pillars: logs, metrics, traces. Plus error tracking + LLM tracing for AI
features. Every service ships with all of them wired up (even if the backend
is just stdout in dev).

---

## Stack defaults

| Pillar          | Default                       | Alternatives                  |
| --------------- | ----------------------------- | ----------------------------- |
| Logs            | structlog / pino / zap → CloudWatch / Loki | Datadog, Splunk |
| Metrics         | Prometheus + Grafana          | CloudWatch, Datadog           |
| Traces          | OpenTelemetry → Tempo / Jaeger / Honeycomb | Datadog APM       |
| Errors          | Sentry                        | Rollbar, Bugsnag              |
| LLM             | Langfuse                      | LangSmith, Helicone           |
| Uptime          | Better Stack / Pingdom / Grafana Synth | self-hosted blackbox  |
| Dashboards      | Grafana                       | Datadog, CloudWatch           |

**Always OpenTelemetry-native** — gives provider portability.

---

## Structured logging

### Python — structlog

```python
# core/logging.py
import logging
import sys
import structlog


def configure_logging(level: str = "INFO") -> None:
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=getattr(logging, level.upper()),
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            getattr(logging, level.upper())
        ),
        cache_logger_on_first_use=True,
    )


log = structlog.get_logger()
```

Per-request binding:

```python
# middleware
import uuid
from starlette.middleware.base import BaseHTTPMiddleware

class ContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        rid = request.headers.get("x-request-id") or str(uuid.uuid4())
        structlog.contextvars.bind_contextvars(
            request_id=rid,
            method=request.method,
            path=request.url.path,
        )
        try:
            response = await call_next(request)
        finally:
            structlog.contextvars.clear_contextvars()
        response.headers["x-request-id"] = rid
        return response
```

### Node — pino

```ts
import pino from 'pino';
export const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  base: { service: 'api', env: process.env.ENV },
  timestamp: pino.stdTimeFunctions.isoTime,
  formatters: { level: (label) => ({ level: label }) },
});
```

### Go — slog

```go
import "log/slog"
import "os"

var Log = slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    Level: slog.LevelInfo,
    AddSource: false,
}))
```

### Rules

- One log line = one JSON object
- Always include: `timestamp`, `level`, `service`, `env`, `request_id`,
  `user_id` (when known)
- Use level meaningfully: DEBUG (dev), INFO (state changes), WARN (recoverable
  abnormal), ERROR (operation failed)
- Never log PII / secrets (filtered at processor level)
- Never `print` / `console.log` in production code

---

## Metrics — Prometheus / OpenTelemetry

### Four golden signals per service

- **Latency**: p50, p95, p99 per route
- **Traffic**: req/s per route
- **Errors**: 5xx rate per route
- **Saturation**: CPU, memory, in-flight requests, DB pool utilisation

### Python — prometheus_client

```python
from prometheus_client import Counter, Histogram

http_requests_total = Counter(
    "http_requests_total", "HTTP requests", ["method", "route", "status"]
)
http_request_duration_seconds = Histogram(
    "http_request_duration_seconds", "HTTP request latency",
    ["method", "route"], buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)
```

### Business metrics (always add these)

- Signups / day, active users / day
- Conversion rate per critical funnel step
- LLM cost per user per day
- Job queue depth + age of oldest job

---

## Tracing — OpenTelemetry

### Python instrumentation

```python
# core/tracing.py
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor


def setup_tracing(app, engine, service_name: str, endpoint: str | None) -> None:
    if not endpoint:
        return
    provider = TracerProvider(resource=Resource.create({"service.name": service_name}))
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint)))
    trace.set_tracer_provider(provider)
    FastAPIInstrumentor.instrument_app(app)
    SQLAlchemyInstrumentor().instrument(engine=engine.sync_engine)
    HTTPXClientInstrumentor().instrument()
```

Manual spans around hot paths:

```python
tracer = trace.get_tracer(__name__)

async def search(query: str) -> list[Result]:
    with tracer.start_as_current_span("search.execute") as span:
        span.set_attribute("search.query.len", len(query))
        rows = await repo.search(query)
        span.set_attribute("search.results", len(rows))
        return rows
```

### Sampling

- Dev: 100%
- Prod: parent-based + ratio (e.g. 5%) + always-on for errors
- High-cardinality attributes (user_id) are fine on spans; never on metrics

---

## Error tracking — Sentry

```python
import sentry_sdk
sentry_sdk.init(
    dsn=os.environ["SENTRY_DSN"],
    environment=settings.env,
    release=settings.version,
    traces_sample_rate=0.05,
    profiles_sample_rate=0.05,
    send_default_pii=False,
)
```

Rules:
- `send_default_pii=False` (always)
- `before_send` hook scrubs known sensitive fields
- Tag with `user.id` (opaque) and `request_id`
- Alert on new issues / regression / spike

---

## LLM observability — Langfuse

```python
from langfuse import Langfuse
lf = Langfuse(public_key=os.environ["LANGFUSE_PUBLIC_KEY"],
              secret_key=os.environ["LANGFUSE_SECRET_KEY"],
              host=os.environ.get("LANGFUSE_HOST"))

async def complete_with_trace(req: CompletionRequest) -> CompletionResponse:
    trace = lf.trace(name="chat", user_id=req.user_id, metadata={"task": req.task})
    gen = trace.generation(
        name=f"llm.{req.task}",
        model=req.model_hint,
        input=req.messages,
    )
    try:
        resp = await provider.complete(req)
        gen.end(output=resp.text, usage={
            "input": resp.input_tokens, "output": resp.output_tokens, "total": resp.input_tokens + resp.output_tokens,
        })
        return resp
    except Exception as e:
        gen.end(level="ERROR", status_message=str(e))
        raise
```

Track per trace: prompt template id + version, cost, latency, tool calls,
final output schema validity, user feedback (thumbs).

---

## Health endpoints

Every service:

```python
@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}                  # liveness — process alive


@router.get("/ready")
async def ready(session: AsyncSession = Depends(get_session)) -> dict[str, str]:
    await session.execute(text("SELECT 1"))   # readiness — deps reachable
    return {"status": "ready"}
```

Liveness probe → restart if fails. Readiness probe → don't route traffic if
fails. Load balancer / orchestrator wired to both.

---

## Dashboards — Grafana

Standard dashboards per service:

1. **Overview**: traffic, errors, latency, saturation
2. **Per-route**: same metrics broken down
3. **Dependencies**: DB pool, Redis ops, downstream API latency
4. **Business**: signups, active users, funnel
5. **AI** (if applicable): LLM cost per hour, p95 latency, cache hit rate,
   tool-call failure rate

Provision as code via Grafana provisioning (JSON + ConfigMap) or
`grafana/terraform-provider-grafana`.

---

## Alerting

Tiered severity:

| Sev | Trigger                                          | Channel                       |
| --- | ------------------------------------------------ | ----------------------------- |
| P1  | Service down, error rate > 5% for 5 min, security alert | PagerDuty / phone        |
| P2  | p99 > SLO for 15 min, queue depth high           | Slack channel #ops-alerts     |
| P3  | Dependency degraded, cost overrun                | Slack channel #ops-info       |

Always include in alert: title, impact, runbook URL, dashboard URL.

Runbooks live in `docs/runbooks/<service>-<scenario>.md`.

---

## SLOs

For each user-facing service:

- Availability: 99.9% monthly
- p95 latency: < 500ms (tune per app)
- Error budget: 0.1% / month → roughly 43 minutes downtime allowed

When budget burns fast → freeze feature work, focus on reliability.

---

## Cost observability

- Compute / storage from cloud billing API → daily Slack post
- LLM cost from Langfuse → daily
- Per-feature cost tagging via labels (`feature=chat`, `feature=search`)
- Alert on month-to-date > budget × pacing

---

## Local dev

`docker-compose.observability.yml` stands up Grafana + Tempo + Loki +
Prometheus locally. Optional but useful for projects with heavy tracing.

```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    volumes: ["./infra/local/prometheus.yml:/etc/prometheus/prometheus.yml:ro"]
    ports: ["9090:9090"]
  grafana:
    image: grafana/grafana:latest
    ports: ["3001:3000"]
    environment: { GF_AUTH_ANONYMOUS_ENABLED: "true", GF_AUTH_ANONYMOUS_ORG_ROLE: Admin }
  tempo:
    image: grafana/tempo:latest
    command: ["-config.file=/etc/tempo.yaml"]
  loki:
    image: grafana/loki:latest
    ports: ["3100:3100"]
```

---

## Never do

- Plain-text logs in production
- Logging raw request bodies (PII risk)
- Sampling errors (always 100%)
- High-cardinality metric labels (user_id, request_id, full URL)
- Health endpoints behind auth
- Dashboards built in UI without ConfigMap / JSON backup
- Alerts without runbooks
