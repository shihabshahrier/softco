# 03 — AI / LLM Integration

LLM is first-class. Real architecture, not a single API call in a controller.
Pair with `10-prompt-engineering.md`.

---

## Contents

- [Provider matrix](#provider-matrix)
- [Model routing strategy](#model-routing-strategy-defaults)
- [Router abstraction — Python](#router-abstraction-python)
- [Streaming pattern — SSE, FastAPI](#streaming-pattern-sse-fastapi)
- [RAG architecture](#rag-architecture)
- [Agentic loop](#agentic-loop-tool-use)
- [Structured output](#structured-output)
- [Multi-agent orchestration](#multi-agent-orchestration-langgraph-pattern)
- [Memory](#memory)
- [Cost controls](#cost-controls)
- [Observability](#observability)
- [Safety / guardrails](#safety--guardrails)
- [Provider switch checklist](#provider-switch-checklist)
- [What never to do](#what-never-to-do)

---

## Provider matrix

| Provider     | Best for                                  | Auth                  |
| ------------ | ----------------------------------------- | --------------------- |
| Anthropic    | Reasoning, code, long context, tool use   | `ANTHROPIC_API_KEY`   |
| OpenAI       | Multimodal, fast iterations, embeddings   | `OPENAI_API_KEY`      |
| Google       | Multimodal, very long context (Gemini)    | `GEMINI_API_KEY` / Vertex |
| AWS Bedrock  | AWS-native, compliance, multi-model       | IAM role              |
| Vertex AI    | GCP-native, Gemini + 3P models            | WIF                   |
| Azure AI     | Enterprise / regulated workloads          | Entra ID              |
| Groq         | Ultra-fast inference open-weight          | `GROQ_API_KEY`        |
| Together     | Open-weight at scale                      | `TOGETHER_API_KEY`    |
| Ollama       | Local dev / on-prem                       | none (URL)            |

Pick by: data residency → cost → latency → capability. Never lock in without
abstraction.

---

## Model routing strategy (defaults)

| Task class                  | Primary             | Cheap fallback     | Heavy fallback     |
| --------------------------- | ------------------- | ------------------ | ------------------ |
| Intent / classification     | Haiku               | Llama 3.1 8B (Groq)| —                  |
| Generation / Q&A            | Sonnet              | GPT-4o-mini        | Llama 3.1 70B      |
| Hard reasoning / planning   | Opus / o1           | Sonnet             | Gemini 2.5 Pro     |
| Code generation             | Sonnet              | Qwen Coder 32B     | DeepSeek Coder     |
| Embeddings                  | Voyage 3 / OpenAI 3-small | Gemini embedding | —              |
| Reranking                   | Cohere Rerank       | Voyage rerank      | —                  |

Always abstract behind a router. Caller asks for **task class**, not model.

---

## Router abstraction (Python)

```python
# ai/router.py
from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol


class TaskClass(StrEnum):
    CLASSIFY = "classify"
    GENERATE = "generate"
    REASON = "reason"
    CODE = "code"


@dataclass(frozen=True, slots=True)
class CompletionRequest:
    task: TaskClass
    system: str
    messages: list[dict]
    max_tokens: int = 1024
    temperature: float = 0.2
    response_schema: dict | None = None  # JSON schema for structured output
    tools: list[dict] | None = None


@dataclass(frozen=True, slots=True)
class CompletionResponse:
    text: str
    tool_calls: list[dict]
    model: str
    input_tokens: int
    output_tokens: int
    cost_usd: float


class LLMProvider(Protocol):
    async def complete(self, req: CompletionRequest) -> CompletionResponse: ...


class Router:
    def __init__(self, providers: dict[TaskClass, list[LLMProvider]]) -> None:
        self._providers = providers

    async def complete(self, req: CompletionRequest) -> CompletionResponse:
        last_err: Exception | None = None
        for p in self._providers[req.task]:
            try:
                return await p.complete(req)
            except (TimeoutError, RateLimitError) as e:
                last_err = e
                continue
        raise RuntimeError("all providers failed") from last_err
```

Every caller uses `router.complete(...)`; never imports a vendor SDK
directly.

---

## Streaming pattern (SSE, FastAPI)

```python
from fastapi import APIRouter
from sse_starlette.sse import EventSourceResponse
from anthropic import AsyncAnthropic

router = APIRouter()
client = AsyncAnthropic()


@router.post("/chat/stream")
async def chat_stream(payload: ChatRequest) -> EventSourceResponse:
    async def events():
        async with client.messages.stream(
            model="claude-sonnet-4-6",
            max_tokens=2048,
            system=SYSTEM_PROMPT,
            messages=payload.messages,
        ) as stream:
            async for text in stream.text_stream:
                yield {"event": "delta", "data": text}
            final = await stream.get_final_message()
            yield {"event": "done", "data": str(final.usage.output_tokens)}

    return EventSourceResponse(events())
```

Always:
- Set a server-side max_tokens cap
- Pipe usage info to logging / Langfuse
- Handle client disconnect (FastAPI handles via async generator cancel)

---

## RAG architecture

```
ingest:  raw_docs → splitter → embedder → vector_store
                                 ↘ metadata index (Postgres)

query:   user_q → query_planner (LLM) → retriever (vector + keyword) →
         reranker → context_builder → answerer (LLM) → response
```

### Chunking rules

- Semantic chunking preferred (LangChain `SemanticChunker`, or unstructured)
- Fallback: 800-token chunks, 150-token overlap
- Preserve metadata: `doc_id`, `page`, `section_title`
- Store original text + embedding + metadata in same row

### Embedding

```python
# ai/embeddings.py
from openai import AsyncOpenAI
client = AsyncOpenAI()

async def embed(texts: list[str], *, model: str = "text-embedding-3-small") -> list[list[float]]:
    resp = await client.embeddings.create(model=model, input=texts)
    return [d.embedding for d in resp.data]
```

Batch: 100 chunks per request. Cost per million tokens: track per project.

### Postgres + pgvector

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE chunks (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_id       uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    content      text NOT NULL,
    embedding    vector(1536) NOT NULL,
    metadata     jsonb NOT NULL DEFAULT '{}',
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX chunks_embedding_hnsw ON chunks USING hnsw (embedding vector_cosine_ops);
CREATE INDEX chunks_doc_id ON chunks (doc_id);
CREATE INDEX chunks_content_fts ON chunks USING GIN (to_tsvector('english', content));
```

### Hybrid retrieval

```python
async def retrieve(query: str, k: int = 20) -> list[Chunk]:
    q_embed = (await embed([query]))[0]
    rows = await session.execute(text("""
        SELECT id, content, metadata,
               (embedding <=> :embed) AS vector_dist,
               ts_rank(to_tsvector('english', content), plainto_tsquery(:q)) AS bm25
        FROM chunks
        ORDER BY (embedding <=> :embed) * 0.7 + (1 - ts_rank(...)) * 0.3
        LIMIT :k
    """), {"embed": q_embed, "q": query, "k": k})
    return [Chunk(**r) for r in rows.mappings()]
```

Then rerank top-k with Cohere Rerank or Voyage; keep top-5 for context.

---

## Agentic loop (tool use)

```python
# ai/agent.py
async def run_agent(
    user_input: str,
    *,
    tools: dict[str, Callable],
    max_steps: int = 8,
) -> AgentResult:
    messages: list[dict] = [{"role": "user", "content": user_input}]
    for step in range(max_steps):
        resp = await router.complete(CompletionRequest(
            task=TaskClass.REASON,
            system=AGENT_SYSTEM_PROMPT,
            messages=messages,
            tools=[t.schema for t in tools.values()],
        ))
        if not resp.tool_calls:
            return AgentResult(text=resp.text, steps=step + 1)
        messages.append({"role": "assistant", "content": resp.text, "tool_calls": resp.tool_calls})
        for tc in resp.tool_calls:
            tool = tools[tc["name"]]
            result = await tool.run(**tc["input"])
            messages.append({"role": "tool", "tool_call_id": tc["id"], "content": result})
    raise AgentError("max steps exceeded")
```

Hard rules:
- Bounded loop (max_steps)
- Timeout per tool call
- Tools have JSON schema validated input
- Side-effecting tools require explicit user confirmation in user-facing
  agents

---

## Structured output

Anthropic / OpenAI both support tool-use as structured output. Define schema
once with Pydantic, share across runtime + tests.

```python
from pydantic import BaseModel

class BillingAnswer(BaseModel):
    invoice_id: str
    amount_cents: int
    status: Literal["paid", "open", "void"]
    explanation: str


async def get_billing_answer(q: str) -> BillingAnswer:
    resp = await router.complete(CompletionRequest(
        task=TaskClass.GENERATE,
        system=BILLING_SYSTEM,
        messages=[{"role": "user", "content": q}],
        tools=[{
            "name": "billing_answer",
            "description": "Return a structured billing answer.",
            "input_schema": BillingAnswer.model_json_schema(),
        }],
    ))
    return BillingAnswer.model_validate(resp.tool_calls[0]["input"])
```

---

## Multi-agent orchestration (LangGraph pattern)

```python
from langgraph.graph import StateGraph, END

class State(TypedDict):
    question: str
    plan: list[str]
    findings: list[dict]
    answer: str | None

def planner(s: State) -> State: ...
def researcher(s: State) -> State: ...
def writer(s: State) -> State: ...
def critic(s: State) -> State: ...

g = StateGraph(State)
g.add_node("plan", planner)
g.add_node("research", researcher)
g.add_node("write", writer)
g.add_node("critic", critic)
g.set_entry_point("plan")
g.add_edge("plan", "research")
g.add_edge("research", "write")
g.add_conditional_edges("write", lambda s: "critic" if not s["answer"] else END)
g.add_edge("critic", "research")
app = g.compile()
```

Use when single-LLM-call won't suffice: planning, multi-step research,
critique loops.

---

## Memory

| Type        | Storage                            | Retention                  |
| ----------- | ---------------------------------- | -------------------------- |
| Short-term  | conversation messages in session   | last N turns / token budget|
| Long-term   | pgvector embeddings of facts       | indefinite, with TTL option|
| Episodic    | structured event log               | for audit + replay         |
| Working     | scratchpad in agent state          | per task                   |

Compaction: when conversation exceeds budget, summarise older turns with a
cheap model; preserve the summary as a single message.

---

## Cost controls

- Cap `max_tokens` per request
- Track input + output tokens per request (Langfuse / homegrown)
- Hard budget per user / day; return graceful error on exceed
- Cache embeddings (deterministic key on content hash)
- Prompt-cache repeated system prompts (Anthropic prompt caching: mark
  `cache_control` on system + tools + long context)

```python
# Anthropic prompt caching
messages = [
    {"role": "user", "content": q},
]
system = [
    {"type": "text", "text": LONG_SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}},
]
```

Run prompt-cache hit-rate metric in observability.

---

## Observability

- Every LLM call traced through Langfuse / Helicone / LangSmith
- Trace fields: `prompt_id`, `model`, `input_tokens`, `output_tokens`, `cost_usd`,
  `latency_ms`, `user_id`, `request_id`
- Sample 100% in dev, 10% sustained in prod (full sample on errors)

---

## Safety / guardrails

Input layer:
- Length cap on user input
- Prompt injection filter (regex + small classifier for high-risk apps)
- PII redaction before sending to LLM if data-residency matters

Output layer:
- Validate against expected JSON schema
- Refuse policy regex (e.g. don't leak system prompt)
- For tool-using agents: allowlist of side-effecting tools per user role

---

## Provider switch checklist

When user wants to switch primary provider:

1. Implement provider behind `LLMProvider` protocol
2. Add to router with the priority they want
3. Run prompt regression suite against new provider
4. Compare latency + cost on a sample
5. Update `AGENT.md` AI section + `docs/TDR-XXXX-llm-routing.md`

---

## What never to do

- Send raw user input directly to a tool-executing LLM without an injection
  defence
- Trust LLM output for SQL, shell, file paths without schema validation +
  allowlist
- Hardcode a single provider's SDK across the codebase
- Skip token / cost tracking
- Use the same prompt for prod and tests without snapshot regression
- Stream LLM output to the client without server-side abort on disconnect
