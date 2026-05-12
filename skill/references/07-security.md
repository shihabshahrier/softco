# 07 — Security

Owns: secrets, auth, OWASP Top 10, supply chain, secure defaults. Load on
audit / auth / payment / compliance work.

---

## Threat model checklist (every project)

Run this in Phase 1 and update each major change:

1. **Data classes**: public / internal / confidential / restricted. Where does
   each live? Encrypted at rest? In transit?
2. **Trust boundaries**: end-user, third-party API, internal services, admin.
3. **Entry points**: every public endpoint, webhook, file upload, queue,
   third-party callback.
4. **Identities**: human users, service accounts, agents (LLM tools).
5. **High-impact assets**: PII, payment, credentials, signing keys.
6. **Attack surface deltas**: what's new this release?

Output `docs/THREAT_MODEL.md` with a STRIDE table per entry point.

---

## OWASP Top 10 (2021) — defaults that block each

| Threat                          | Default control                                          |
| ------------------------------- | -------------------------------------------------------- |
| A01 Broken Access Control       | Server-side authz on every endpoint; tenant scoping; tests |
| A02 Cryptographic Failures      | TLS 1.2+ only; argon2id; KMS for keys                    |
| A03 Injection                   | Parameterised queries; Zod/Pydantic at boundary; escape outputs |
| A04 Insecure Design             | Threat model; ADRs; least privilege                      |
| A05 Security Misconfig          | Helmet/CSP; default-deny CORS; no debug in prod          |
| A06 Vulnerable Components       | Dependabot; weekly audit; image scan                     |
| A07 Auth Failures               | MFA; rate-limit; short JWT; refresh rotation; lockout    |
| A08 Software & Data Integrity   | Signed commits; SLSA-style provenance; pinned deps       |
| A09 Logging & Monitoring        | Structured logs; SIEM; alerting on auth anomalies        |
| A10 SSRF                        | Egress allowlist; metadata endpoint block; URL validation|

---

## Secrets management

Rules:
- **Never** commit secrets. Period.
- `.env` always gitignored. `.env.example` committed.
- Production secrets in cloud secrets manager (AWS SM / GCP SM / Azure KV /
  Vault).
- Rotate every 90 days; rotation hooks in Terraform where supported.
- Inject at runtime (ECS task secret refs, K8s External Secrets) — never bake
  into image.
- Logging filters strip known secret patterns.

Detection:
- `gitleaks` pre-commit hook
- `trufflehog` in CI
- GitHub secret scanning enabled + push protection

If a secret leaks: rotate immediately → invalidate exposed copies → audit
access logs → post-mortem in `docs/incidents/`.

---

## Authentication

### Defaults

- Library, not roll-your-own: Clerk / NextAuth / Supabase Auth / Auth0 /
  Cognito.
- If a library cannot be used:
  - Password hashing: argon2id (params: `t=2, m=64MiB, p=1` minimum)
  - JWT: HS256 with rotating key or RS256 with KMS; `exp` ≤ 1 hour
  - Refresh tokens: opaque, stored hashed, single-use rotation, family
    tracking for replay detection
  - Account lockout / progressive delay after N failed attempts
  - MFA via TOTP (RFC 6238) or WebAuthn

### JWT minimum claims

```json
{
  "iss": "softco-api",
  "sub": "<user-id>",
  "aud": "softco-web",
  "iat": 1715200000,
  "exp": 1715203600,
  "jti": "<unique-id>",
  "tenant_id": "<uuid>"
}
```

Validate every claim server-side, including `iss` and `aud`.

### Sessions vs JWT

- Web app + same-origin API → consider HttpOnly Secure SameSite=Strict
  session cookies + server-side store (Redis). Simpler revocation.
- Mobile / multi-client / cross-origin → JWT + short-lived access + rotating
  refresh.

---

## Authorization

Always enforced on the **server**. Client-side checks are UX only.

Patterns:
- **RBAC**: roles assigned to users; permissions assigned to roles
- **ABAC**: attribute-based for fine-grained ("owner can edit, viewer can
  read")
- **Tenant scoping**: every query includes `tenant_id`; enforce via RLS or
  middleware

Implementation rule: **deny by default**. Endpoint without explicit policy
returns 403.

```python
# api/deps.py
async def require_permission(perm: str):
    async def _dep(user: User = Depends(current_user)) -> User:
        if perm not in user.permissions:
            raise Forbidden(f"missing permission: {perm}")
        return user
    return _dep

# usage
@router.post("/projects/{id}/archive", dependencies=[Depends(require_permission("project:archive"))])
async def archive(...): ...
```

---

## Input validation

- Parse at boundary (Pydantic, Zod, struct + validator). Internal code trusts
  parsed types.
- Length caps on every string. Size caps on every payload.
- Allowlist over blocklist (file types, URL schemes, redirect targets).
- IDs in path/query validated as expected format before any DB lookup.

```python
class CreatePost(BaseModel):
    title: Annotated[str, StringConstraints(min_length=1, max_length=200)]
    body: Annotated[str, StringConstraints(min_length=1, max_length=10_000)]
    tags: Annotated[list[str], Field(max_length=10)]
```

---

## SQL injection

- Always parameterise. Never string-format SQL.
- ORM queries by default; raw SQL only with `:bind` params.
- Reject identifier interpolation from user input (table / column names).

```python
# good
await session.execute(text("SELECT id FROM users WHERE email = :e"), {"e": email})
# bad — never
session.execute(f"SELECT * FROM users WHERE email = '{email}'")
```

---

## XSS

- Never `innerHTML` / `dangerouslySetInnerHTML` with user input
- Use framework-default escaping (React auto-escapes)
- For markdown / rich text: render via library (`marked` + `DOMPurify`,
  `markdown-it` + sanitiser); allowlist tags + attrs
- CSP header that blocks inline scripts (or uses nonce-based inline)

```
Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-{n}';
  style-src 'self' 'nonce-{n}'; img-src 'self' data: https:; connect-src 'self' https://api.example.com;
  frame-ancestors 'none'; base-uri 'self'; object-src 'none'
```

---

## CSRF

- API uses Bearer JWT → CSRF immune (no cookie auth)
- API uses cookie → require `SameSite=Strict` and CSRF token on state-changing
  requests
- Webhook endpoints verify signature, not session

---

## Rate limiting

Every public endpoint. Layered:

- L7 edge: CloudFront / Cloud Armor / Nginx
- App: per-user + per-IP token bucket via Redis

```python
from fastapi import Depends
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
# app.state.limiter = limiter; add SlowAPIMiddleware

@router.post("/auth/login")
@limiter.limit("5/minute")
async def login(...): ...
```

Stricter limits on `/auth/*` and `/password-reset`.

---

## CORS

Production: explicit allowlist of known origins. Never `*` with credentials.

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.example.com"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
    max_age=600,
)
```

---

## Security headers (set on every response)

| Header                              | Value                                  |
| ----------------------------------- | -------------------------------------- |
| `Strict-Transport-Security`         | `max-age=63072000; includeSubDomains; preload` |
| `X-Content-Type-Options`            | `nosniff`                              |
| `X-Frame-Options`                   | `DENY`                                 |
| `Referrer-Policy`                   | `strict-origin-when-cross-origin`      |
| `Permissions-Policy`                | `camera=(), microphone=(), geolocation=()` (tune per app) |
| `Content-Security-Policy`           | see above                              |
| `Cross-Origin-Opener-Policy`        | `same-origin`                          |
| `Cross-Origin-Resource-Policy`      | `same-origin`                          |

---

## File uploads

- Allowlist MIME + extension; verify magic bytes
- Cap size at the proxy + app level
- Scan with ClamAV / cloud AV before exposing
- Store in S3 / GCS with random keys; never the original filename
- Serve via signed URLs with short TTL
- Never serve uploads from the app origin without `Content-Disposition:
  attachment` + sandboxed subdomain

---

## SSRF defence

When fetching URLs supplied by users (webhooks, image proxy, OG preview):

- Allowlist schemes (`http`, `https` only)
- Resolve DNS, reject private CIDRs (`10/8`, `172.16/12`, `192.168/16`,
  `169.254.169.254`, `127/8`)
- Bind outbound to a non-default egress with metadata blocked
- Timeout + size cap on the response

---

## Supply chain

- Pin all dependencies (lockfile committed)
- Verify integrity (npm `--frozen-lockfile`, `uv sync --frozen`)
- Signed container images (cosign) where infra supports it
- SBOM generated in CI (`docker build --sbom=true`)
- Renovate / Dependabot weekly
- Trivy image scan blocks on HIGH+

---

## Logging — what NOT to log

Never log:
- Passwords, tokens, keys
- Full credit card / bank account
- Session cookies
- Authorization headers
- LLM-generated user PII without redaction

Log:
- User ID (opaque), request ID, route, method, status, duration
- Auth events: login success/fail, MFA, password reset
- Authz failures with reason

---

## AI-specific risks

- **Prompt injection**: input filtering + system prompt design + output
  validation. Never give an injectable LLM admin-level tools.
- **Data exfiltration via tool**: tools that fetch URLs / make API calls must
  allowlist destinations and redact secrets.
- **Model output trust**: never `exec` / `eval` LLM output. Never use it as
  SQL / shell / file paths without schema validation.
- **PII leak**: redact before sending to third-party models if data residency
  matters.
- **Token cost DOS**: per-user rate limit + budget cap.

---

## Incident response

When an issue is reported / detected:

1. Triage severity (data loss / outage / leak / minor)
2. Contain — rotate creds, disable feature, scale down attacker
3. Eradicate — patch, redeploy
4. Recover — restore, monitor
5. Post-mortem in `docs/incidents/YYYYMMDD-<slug>.md`:
   - Timeline
   - Root cause
   - Impact
   - Detection delay
   - Action items with owners + dates
6. Track action items to completion

---

## Compliance quick-map

| Regime  | Key controls                                                  |
| ------- | ------------------------------------------------------------- |
| GDPR    | Lawful basis; DPA; data export + erase; breach notification 72h |
| HIPAA   | BAA with vendors; encryption at rest + transit; audit logs    |
| SOC2    | Access reviews; change mgmt; monitoring; vendor mgmt          |
| PCI-DSS | Tokenise card data; segment cardholder env; logging; quarterly scans |

Confirm scope with user before claiming compliance. Most projects need
**GDPR-ready posture** even if not formally certified.

---

## Never do

- Roll your own crypto
- Disable TLS verification in any prod code
- `eval` / `exec` of any user-derived string
- Wide-open S3 / GCS buckets
- IAM `*` in prod
- Skipping the rate-limiter on auth endpoints
- Logging PII without redaction
- Trusting client-supplied user ID / role / tenant ID
