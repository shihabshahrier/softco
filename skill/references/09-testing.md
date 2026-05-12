# 09 — Testing

Test-first. Coverage ≥ 80% enforced in CI. Patterns per stack.

---

## Contents

- [Pyramid](#pyramid)
- [Python — pytest + httpx + testcontainers](#python--pytest--httpx--testcontainers)
- [Node — vitest + supertest](#node--vitest--supertest)
- [Go — table tests + httptest](#go--table-tests--httptest)
- [E2E — Playwright](#e2e--playwright)
- [Test data](#test-data)
- [Snapshot testing](#snapshot-testing)
- [Performance / load](#performance--load)
- [Mutation testing](#mutation-testing-optional-high-value)
- [What never to do](#what-never-to-do)

---

## Pyramid

```
                  /\
                 /e2e\         few, slow, end-to-end critical flows
                /------\
               / inte-  \      moderate; real DB, real Redis (testcontainers)
              /  gration \
             /------------\
            /     unit     \   many, fast, pure logic
           /----------------\
```

Targets:
- Unit: ≥ 90% of business logic
- Integration: every API endpoint
- E2E: every critical user flow (signup, primary action, payment)
- AI: every shipped prompt has regression cases

---

## Python — pytest + httpx + testcontainers

### Layout

```
tests/
├── conftest.py
├── unit/
│   ├── domain/
│   └── core/
├── integration/
│   ├── api/
│   └── db/
├── e2e/
└── ai/
    ├── cases/
    └── test_prompts.py
```

### `conftest.py`

```python
from __future__ import annotations

import asyncio
import os
import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from testcontainers.postgres import PostgresContainer

from src.main import app
from src.db.session import get_session
from src.db.base import Base


@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="session")
def pg_container():
    with PostgresContainer("pgvector/pgvector:pg16", user="t", password="t", dbname="t") as c:
        os.environ["DATABASE_URL"] = c.get_connection_url().replace("postgresql://", "postgresql+asyncpg://")
        yield c


@pytest_asyncio.fixture(scope="session")
async def engine(pg_container):
    eng = create_async_engine(os.environ["DATABASE_URL"], pool_pre_ping=True)
    async with eng.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield eng
    await eng.dispose()


@pytest_asyncio.fixture
async def session(engine) -> AsyncSession:
    Session = async_sessionmaker(engine, expire_on_commit=False)
    async with Session() as s:
        yield s
        await s.rollback()


@pytest_asyncio.fixture
async def client(session) -> AsyncClient:
    app.dependency_overrides[get_session] = lambda: session
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        yield c
    app.dependency_overrides.clear()
```

### Unit example

```python
# tests/unit/domain/test_password.py
import pytest
from src.core.security import hash_password, verify_password

def test_hash_then_verify():
    h = hash_password("correct horse battery staple")
    assert verify_password("correct horse battery staple", h) is True

def test_verify_wrong():
    h = hash_password("a")
    assert verify_password("b", h) is False

@pytest.mark.parametrize("pw", ["", " ", "short"])
def test_hash_rejects_short(pw):
    with pytest.raises(ValueError):
        hash_password(pw)
```

### Integration example

```python
# tests/integration/api/test_users.py
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_create_user(client: AsyncClient):
    r = await client.post("/v1/users", json={
        "email": "alice@example.com",
        "password": "correct horse battery staple",
    })
    assert r.status_code == 201
    body = r.json()
    assert body["email"] == "alice@example.com"
    assert "password" not in body
    assert "id" in body

@pytest.mark.asyncio
async def test_create_user_duplicate(client: AsyncClient):
    payload = {"email": "bob@example.com", "password": "correct horse battery staple"}
    r1 = await client.post("/v1/users", json=payload)
    r2 = await client.post("/v1/users", json=payload)
    assert r1.status_code == 201
    assert r2.status_code == 409
    assert r2.json()["error"]["code"] == "CONFLICT"
```

### AI regression

```python
# tests/ai/test_prompts.py
import json
import pathlib
import pytest
from src.ai.router import router, CompletionRequest, TaskClass
from src.ai.prompts import BILLING_SYSTEM

CASES = list(pathlib.Path("tests/ai/cases").glob("*.json"))

@pytest.mark.parametrize("case_path", CASES, ids=lambda p: p.stem)
@pytest.mark.asyncio
async def test_billing_answer(case_path):
    case = json.loads(case_path.read_text())
    resp = await router.complete(CompletionRequest(
        task=TaskClass.GENERATE,
        system=BILLING_SYSTEM,
        messages=case["messages"],
        max_tokens=500,
        temperature=0,
    ))
    data = json.loads(resp.text)
    for assertion in case["assertions"]:
        if assertion["type"] == "json_key_eq":
            assert data[assertion["key"]] == assertion["value"]
        elif assertion["type"] == "contains":
            assert assertion["value"].lower() in resp.text.lower()
        elif assertion["type"] == "schema":
            from jsonschema import validate
            validate(data, schema=assertion["schema"])
```

Case file:

```json
{
  "messages": [{"role": "user", "content": "What's invoice INV-123?"}],
  "assertions": [
    { "type": "json_key_eq", "key": "invoice_id", "value": "INV-123" },
    { "type": "schema", "schema": { "type": "object", "required": ["invoice_id", "status"] } }
  ]
}
```

Adversarial cases: prompt injection, empty input, oversized, contradictory.

---

## Node — vitest + supertest

```ts
// tests/integration/users.test.ts
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';

const app = createApp();

describe('POST /v1/users', () => {
  it('creates a user', async () => {
    const r = await request(app.callback()).post('/v1/users').send({
      email: 'alice@example.com',
      password: 'correct horse battery staple',
    });
    expect(r.status).toBe(201);
    expect(r.body).toMatchObject({ email: 'alice@example.com' });
    expect(r.body.password).toBeUndefined();
  });
});
```

Frontend component:

```tsx
// components/login-form.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { LoginForm } from './login-form';

it('shows validation error on bad email', async () => {
  render(<LoginForm onSubmit={vi.fn()} />);
  await userEvent.type(screen.getByLabelText('Email'), 'nope');
  await userEvent.click(screen.getByRole('button', { name: /sign in/i }));
  expect(await screen.findByRole('alert')).toHaveTextContent(/email/i);
});
```

---

## Go — table tests + httptest

```go
func TestCreateUser(t *testing.T) {
    cases := []struct {
        name      string
        body      string
        wantCode  int
    }{
        {"ok", `{"email":"a@b.com","password":"correct horse battery staple"}`, 201},
        {"bad email", `{"email":"nope","password":"correct horse battery staple"}`, 400},
        {"missing", `{}`, 400},
    }
    r := router.New(testCfg(t))
    for _, c := range cases {
        t.Run(c.name, func(t *testing.T) {
            req := httptest.NewRequest("POST", "/v1/users", strings.NewReader(c.body))
            req.Header.Set("Content-Type", "application/json")
            w := httptest.NewRecorder()
            r.ServeHTTP(w, req)
            if w.Code != c.wantCode { t.Fatalf("got %d want %d", w.Code, c.wantCode) }
        })
    }
}
```

Real DB via `testcontainers-go`.

---

## E2E — Playwright

```ts
// e2e/signup.spec.ts
import { test, expect } from '@playwright/test';

test('user signs up and lands on dashboard', async ({ page }) => {
  await page.goto('/signup');
  await page.getByLabel('Email').fill('e2e+signup@example.com');
  await page.getByLabel('Password').fill('correct horse battery staple');
  await page.getByRole('button', { name: 'Create account' }).click();
  await expect(page).toHaveURL(/\/dashboard/);
  await expect(page.getByRole('heading', { name: /welcome/i })).toBeVisible();
});
```

`playwright.config.ts`: trace on retry, screenshot on failure, mobile viewport
projects.

Run E2E against the **dev environment after deploy**, not local — closer to
prod behaviour, catches infra regressions.

---

## Test data

- Builders / factories, not fixtures pasted everywhere

```python
# tests/factories.py
from datetime import datetime, timezone
from uuid import uuid4
from src.db.models.user import User

def make_user(**overrides) -> User:
    defaults = {
        "id": uuid4(),
        "email": f"user-{uuid4().hex[:8]}@example.com",
        "password_hash": "$argon2id$...",
        "created_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc),
    }
    return User(**(defaults | overrides))
```

- Hypothesis / fast-check for property-based tests on parsers, encoders,
  invariants.

---

## Snapshot testing

Use sparingly. Good for:
- Rendered markdown / HTML structure
- Generated SQL from query builder
- LLM structured outputs (with care)

Bad for: brittle UI snapshots that change with every refactor.

---

## Performance / load

For services with stated RPS targets:

- `k6` or `locust` script in `perf/` with realistic scenarios
- Runs nightly against dev / staging
- Asserts p95 latency under target at target RPS
- Results posted to Grafana dashboard

---

## Mutation testing (optional, high-value)

When auth / payment / billing is critical: `mutmut` (Python) / `stryker` (JS)
to verify tests actually catch bugs.

---

## What never to do

- Tests sharing mutable state without cleanup
- Mocking the database when integration tests are feasible
- Reaching across module boundaries in tests (test public API only)
- Snapshotting full DOM
- Time-dependent tests without freezing time (`freezegun`, `vi.useFakeTimers`)
- Skipping flaky tests instead of fixing them
- Committing `.only` / `fdescribe` / `pytest.mark.skip` without reason
