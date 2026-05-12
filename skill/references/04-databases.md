# 04 — Databases

Schema design + ORM patterns + migrations. Schema is designed in
`docs/DB_SCHEMA.md` **before** any model code.

---

## Engine selection

| Need                                    | Engine                          |
| --------------------------------------- | ------------------------------- |
| General relational                      | Postgres 16+ (default)          |
| Multi-tenant SaaS                       | Postgres + RLS                  |
| Heavy writes, simple key-access         | DynamoDB / ScyllaDB             |
| Document-shaped data, schema flexibility| MongoDB / Firestore             |
| Cache / queue / pub-sub                 | Redis 7+ / Valkey               |
| Vector (embeddings)                     | pgvector / Pinecone / Qdrant    |
| Graph                                   | Neo4j                           |
| Time-series                             | TimescaleDB / Influx            |
| Search                                  | OpenSearch / Typesense / MeiliSearch |

**Default**: Postgres + pgvector covers 90% of projects. Add a second store
only when a clear requirement justifies it (cost, latency, query shape).

---

## Schema design rules

1. UUID v7 primary keys (sortable, no hot index page)
2. `created_at` + `updated_at` `timestamptz` on every row
3. `deleted_at timestamptz` for soft-delete tables only (most tables: hard
   delete)
4. Foreign keys with explicit `ON DELETE` (CASCADE, SET NULL, RESTRICT)
5. Indexes deliberate — every index has a query it serves
6. `NOT NULL` by default; nullable is the exception
7. Enum-shape columns use a `CHECK (col IN (...))` or Postgres `ENUM` type
8. Money in cents (`bigint`), not float
9. Phone numbers stored E.164 as text
10. Timezone-aware timestamps only (`timestamptz`)
11. JSONB for flexible / sparse attributes; never for queryable hot data
12. Surrogate keys for app, natural keys for `UNIQUE` constraints

---

## Migrations

| Stack    | Tool             |
| -------- | ---------------- |
| Python   | Alembic          |
| Node     | Prisma Migrate / Drizzle |
| Go       | golang-migrate / atlas   |
| Multi-lang | Flyway         |

Rules:
- One migration per logical change
- Migrations are **forward-only in prod**; rollback is via PITR + redeploy
- Every migration tested up + down in CI against a real DB
- No data backfill in DDL migration — separate data migration script
- Online migrations for prod (no `ALTER TABLE` that locks > 100ms):
  - Add column with default → use nullable + backfill + set NOT NULL
  - Index creation: `CREATE INDEX CONCURRENTLY`
  - Rename → expand-contract (add new, dual-write, backfill, swap, drop old)

### Alembic example

```python
# packages/db/migrations/versions/20260512_0001_create_users.py
from alembic import op
import sqlalchemy as sa

revision = "20260512_0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute('CREATE EXTENSION IF NOT EXISTS "pgcrypto"')
    op.create_table(
        "users",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True),
                  server_default=sa.text("gen_random_uuid()"), primary_key=True),
        sa.Column("email", sa.Text(), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("email", name="users_email_key"),
    )


def downgrade() -> None:
    op.drop_table("users")
```

---

## SQLAlchemy 2 (async) model

```python
from __future__ import annotations

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import String, DateTime, func
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(PgUUID(as_uuid=True), primary_key=True, default=uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(256), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(),
        onupdate=func.now(), nullable=False
    )
```

---

## Repository pattern

```python
# domain/users/repository.py
from __future__ import annotations

from uuid import UUID
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...db.models.user import User
from ...core.errors import NotFound


class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._s = session

    async def by_id(self, user_id: UUID) -> User:
        row = await self._s.get(User, user_id)
        if row is None:
            raise NotFound("user not found", details={"id": str(user_id)})
        return row

    async def by_email(self, email: str) -> User | None:
        stmt = select(User).where(User.email == email.lower())
        return (await self._s.execute(stmt)).scalar_one_or_none()

    async def create(self, *, email: str, password_hash: str) -> User:
        user = User(email=email.lower(), password_hash=password_hash)
        self._s.add(user)
        await self._s.flush()
        return user
```

Services orchestrate; repositories are the only place SQL lives.

---

## Postgres-specific patterns

### Row-Level Security (multi-tenant)

```sql
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

CREATE POLICY project_tenant_isolation ON projects
    USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

Set `app.tenant_id` per session at start of request (middleware sets a
`SET LOCAL`). Tests verify RLS by querying as a different tenant.

### Connection pooling

- App-level pool: SQLAlchemy `pool_size=10, max_overflow=20`
- Server-side: PgBouncer in transaction-pooling mode for short transactions
- Never use prepared statements with PgBouncer transaction mode without
  `prepare_threshold=0` (asyncpg)

### Performance indexes

| Query shape                                  | Index                                  |
| -------------------------------------------- | -------------------------------------- |
| Equality + range on (a, b)                   | `(a, b)`                               |
| Partial (most rows are X)                    | `... WHERE status = 'active'`          |
| Sorted recent rows                           | `(created_at DESC)`                    |
| Trigram search                               | `USING gin (col gin_trgm_ops)`         |
| Vector ANN                                   | `USING hnsw (embedding vector_cosine_ops)` |
| Full-text                                    | `USING gin (to_tsvector('english', col))` |

Always `EXPLAIN ANALYZE` slow queries; never guess.

### Transactions

- Default: SQLAlchemy `AsyncSession` autoflush, single transaction per request
- `SERIALIZABLE` only for narrow money-moving flows; retry on serialization
  failure
- Avoid long transactions (> 5s) — they hold locks and block VACUUM

---

## MongoDB patterns

When document model wins:

- One collection per aggregate root
- Embed when always-read-together + bounded size; reference when shared
- Compound indexes match query shape; use `explain('executionStats')` to verify
- Schema validation via `$jsonSchema` validator on collection
- Mongoose / Beanie / Motor for typed access
- Migrations: separate scripts versioned in repo; don't lean on driver auto-
  migrations

---

## Redis patterns

| Use case          | Pattern                                          |
| ----------------- | ------------------------------------------------ |
| Cache             | `SETEX key ttl value`; consistent key namespace `app:v1:user:{id}` |
| Rate limit        | Sliding window via sorted-set or token bucket via Lua |
| Lock              | Redlock (multi-node) or single-instance `SET NX PX` |
| Pub/sub           | `PUBLISH` / `SUBSCRIBE`; Redis Streams for durable |
| Session           | Hash per session; TTL refresh on activity        |
| Queue             | Use BullMQ / arq / asynq, not raw lists          |

Rules:
- TTL on every key (no orphan growth)
- Memory cap configured (`maxmemory` + `allkeys-lru`)
- Pipelines / MGET for batch reads
- Never store secrets in Redis (it's a cache, not a vault)

---

## Vector stores

| Store        | When                                          |
| ------------ | --------------------------------------------- |
| pgvector     | < 10M vectors, already on Postgres            |
| Qdrant       | Self-hosted, mid-scale, rich filters          |
| Pinecone     | Managed, serverless, simple                   |
| Weaviate     | Hybrid + modules + GraphQL                    |
| Milvus       | Very large scale, billions of vectors         |

For pgvector index choice:

- < 100k rows: brute force / no index
- 100k – 10M: HNSW with `m=16, ef_construction=64`, query `ef_search=40`
- IVFFlat only when you need exact rebuild control

---

## Backup + recovery

- RDS: PITR enabled; daily snapshots; 7+ day retention
- Self-hosted: `pg_dump` daily to S3 with lifecycle + monthly full + WAL
  archiving for PITR
- **Test restore quarterly** — backup that never restored is not a backup
- Document RPO + RTO in `INFRA.md`

---

## What never to do

- `SELECT *` in production code
- Implicit casts on indexed columns (`WHERE id = '123'` against `bigint`)
- Foreign keys without indexes on the child side
- `SERIAL` / `bigserial` PKs in new schemas (use UUID v7)
- Storing currency as float
- DDL changes without a migration file
- Multi-row update without a `WHERE` (use a transaction + dry-run query)
- Trusting client-supplied IDs without tenant scoping
- Running migrations from a developer machine to prod
