# 12 — Verification (prove it runs)

Green unit tests are necessary, not sufficient. A module is **not done** until
SoftCo has *run the thing* and observed it behave. This reference is the
live-proof discipline: boot it, hit it, watch it, capture evidence, then claim
done. Load when finishing any module, fix, extend, or deploy.

`09-testing.md` is how to *write* tests. This is how to *prove the running
system works* — a different axis. Both are required.

---

## Contents

- [The cardinal rule](#the-cardinal-rule)
- [Levels of proof](#levels-of-proof)
- [The Verification Gate](#the-verification-gate)
- [Running the system](#running-the-system)
- [Browser verification](#browser-verification)
- [AI-feature verification](#ai-feature-verification)
- [Evidence to show the user](#evidence-to-show-the-user)
- [Per-mode verification](#per-mode-verification)
- [Anti-patterns](#anti-patterns)

---

## The cardinal rule

> Never tell the user a feature works until you have run it and seen it work.

"Tests pass" is a claim about code. "I started the server, called the endpoint,
got `201` with the expected body" is a claim about the *running system*. Only
the second discharges the promise. If SoftCo cannot run it (no runtime in the
environment, missing credential), say so explicitly — never imply verification
that did not happen.

---

## Levels of proof

Pick the highest level reachable in the current environment. Higher is stronger.

| Level | Proof | Example |
| ----- | ----- | ------- |
| L0 | Static only | type-check + lint pass |
| L1 | Unit/integration green | `pytest` / `vitest` / `go test` pass with real coverage |
| L2 | Process boots | dev server starts, `/health` returns `200`, no crash on startup |
| L3 | Behavior observed | call the real endpoint / CLI, assert response; query the DB and see the row |
| L4 | User flow observed | drive the UI in a real browser, screenshot the result state |
| L5 | Deployed + canary | live URL responds, smoke passes, metrics nominal post-deploy |

**Minimum gate to claim a module done: L3.** Frontend/user-facing feature: L4.
Shipping a release: L5.

---

## The Verification Gate

Runs at the end of every Phase 3 module loop, before "Module X done. Ready for
next?". The gate is a short checklist SoftCo executes and reports:

```
[ ] lint + type-check clean
[ ] unit + integration tests green (paste the pass count)
[ ] process boots clean (start it; capture startup log; /health 200)
[ ] behavior probed (the new capability exercised against the running system)
[ ] evidence captured (response body / DB row / screenshot / CLI output)
```

Report format after a module:

```markdown
### Verification — <module>
- Tests: 24 passed, 0 failed (coverage 87%)
- Boot: server up on :8000, /health → 200 in 12ms
- Behavior: POST /v1/users → 201, body has id+email, no password leak
- DB: row present in users (id=…), password_hash is argon2id, not plaintext
- Evidence: <paste trimmed output / screenshot path>
```

If any line cannot be completed, state which and why — do not silently drop it.

---

## Running the system

Always prefer the project's own entrypoints (the `Makefile` SoftCo wrote in
Phase 2) over ad-hoc commands.

```bash
make dev          # or: docker compose up -d
# wait for ready, then probe:
curl -fsS localhost:8000/health         # expect 200
curl -fsS localhost:8000/ready          # expect 200 (deps reachable)
```

Backend behavior probe (no browser needed):

```bash
# create then read back — prove the write path end to end
curl -fsS -X POST localhost:8000/v1/users \
  -H 'content-type: application/json' \
  -d '{"email":"verify@example.com","password":"correct horse battery staple"}' | jq
# assert: 201, has id, no password field
```

Database side-effect check (prove persistence, not just the HTTP echo):

```bash
docker compose exec -T db psql -U app -d app \
  -c "select id, email, left(password_hash,9) from users where email='verify@example.com';"
# assert: one row, password_hash starts with $argon2id, never the plaintext
```

CLI tools: run the binary against a fixture and diff the output. Libraries with
no process: write a tiny throwaway driver script that imports the public API and
prints results, run it, then delete it.

Always tear down: `docker compose down -v` / stop the dev server when done.

---

## Browser verification

For any user-facing flow (L4). Use the Playwright MCP server if available;
otherwise a disposable Playwright script. This is SoftCo's answer to a live QA
pass — drive the real UI, assert the visible end state, screenshot it.

```ts
// e2e/_verify.spec.ts  (throwaway — delete or fold into the suite after)
import { test, expect } from '@playwright/test';

test('signup lands on dashboard', async ({ page }) => {
  await page.goto('http://localhost:3000/signup');
  await page.getByLabel('Email').fill('verify@example.com');
  await page.getByLabel('Password').fill('correct horse battery staple');
  await page.getByRole('button', { name: 'Create account' }).click();
  await expect(page).toHaveURL(/\/dashboard/);
  await expect(page.getByRole('heading', { name: /welcome/i })).toBeVisible();
  await page.screenshot({ path: 'verify-dashboard.png', fullPage: true });
});
```

```bash
npx playwright test e2e/_verify.spec.ts --reporter=line
```

Read the screenshot back (the Read tool renders images) and confirm the UI is
not broken — empty states, overflow, missing styles, console errors. A 200 that
renders a blank page is not a pass.

Capture and check the browser console for errors during the flow; a flow that
"works" while throwing uncaught errors is not verified.

---

## AI-feature verification

LLM features fail in ways tests miss. Beyond the regression cases in
`09-testing.md`, at the gate:

- Run the real prompt against the real provider once with a representative input;
  read the actual output, not a mock.
- Confirm structured output **parses** every time across 3–5 varied inputs.
- Fire one adversarial input (injection / empty / oversized) and confirm the
  guardrail holds and the system degrades gracefully.
- Log token + latency for the probe; confirm it is within the budget set in the
  TDR. Flag if not.

---

## Evidence to show the user

Verification is worthless if invisible. After the gate, surface concise
evidence — not a wall of logs:

- the test pass/fail counts and coverage number
- the one decisive request/response (trimmed) or the screenshot
- the DB row proving the side effect
- anything that did **not** verify, named plainly

This is what lets the user trust "done" without re-checking by hand — and what
separates SoftCo from a generator that emits plausible code and hopes.

---

## Per-mode verification

| Mode | Required level | Decisive proof |
| ---- | -------------- | -------------- |
| Greenfield module | L3 (L4 if UI) | endpoint probed + DB side effect, or UI screenshot |
| Fix | L3 | the failing repro now passes *against the running system*, plus its regression test |
| Extend | L3/L4 | new capability exercised live + existing flows still pass (no regression) |
| Infra | L2→L5 | `terraform plan` clean; after apply, the live resource answers |
| Deploy / canary | L5 | live URL smoke passes; error rate + latency nominal for the watch window |

Fix mode specifically: reproduce the bug live **first** (watch it fail), apply
the fix, then watch the same steps pass. A fix verified only by a new green unit
test, without re-running the original failing scenario, is incomplete.

---

## Anti-patterns

- Claiming "the feature works" having only run unit tests.
- "Should work" / "this will return 201" — phrasing that implies a run that did
  not happen.
- Treating a `200` as success without inspecting the body / rendered page.
- Skipping the DB check, so an endpoint that echoes input but never persists
  passes review.
- Leaving verification scripts (`_verify.spec.ts`, throwaway drivers) committed
  as if they were the real suite — fold the keepers into the suite, delete the
  rest.
- Not tearing down spun-up containers/servers, leaking ports between modules.
- Hiding what failed to verify inside an otherwise green report.
