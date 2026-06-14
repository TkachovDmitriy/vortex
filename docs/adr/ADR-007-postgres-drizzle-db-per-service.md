# ADR-007: Postgres + Drizzle, database-per-service

- **Status:** Accepted
- **Date:** 2026-06-11
- **Deciders:** project owner

## Context

`orders` (and later other services) need to persist data. Three coupled
questions must be settled:

1. **Which database engine?**
2. **Which data-access layer** on top of Bun (ADR-001)?
3. **How is data ownership split** across services?

The data itself is deliberately trivial (golden rule #3 — dummy endpoints with
intent); the *point* is to demonstrate the **database-per-service** boundary and
a clean, typed persistence layer that survives compose → kind → managed
("same app runs at every stage").

## Decision

**Postgres** as the engine, **Drizzle** (`drizzle-orm/bun-sql`) as the
data-access layer, and **database-per-service** ownership.

- **Postgres** — the cloud-native default; ubiquitous, well-understood, runs
  trivially as a container locally and as a managed service later.
- **Drizzle via `drizzle-orm/bun-sql`** — a light, typed SQL layer that uses
  Bun's native SQL driver (no extra pg client). SQL-first (not a heavy ORM),
  schema-as-TypeScript, and a simple migration story (`drizzle-kit`).
- **Database-per-service** — each owning service has its **own** database and is
  the *only* writer/reader of it. Services never reach into another service's
  DB; they exchange data only over REST (ADR-003) / NATS (ADR-006).

In Phase 1 the per-service databases may run as separate logical databases in one
Postgres container (cheap locally); the **boundary is enforced in the
architecture**, not by separate servers. Physical separation is a later/managed
concern.

## Consequences

**Positive**

- Clear service autonomy — independent schema, migrations, and deploy per service
  (reinforces ADR-008's "independent services in a monorepo").
- Drizzle keeps SQL visible and types end-to-end without ORM heaviness or a
  generated client.
- `drizzle-orm/bun-sql` rides Bun's native driver — one fewer dependency, fast.
- Postgres is portable across every stage (compose → kind → managed).

**Negative / risks**

- No cross-service joins or DB-level foreign keys across boundaries — by design.
  Cross-service consistency is handled via events (ADR-006), not transactions.
  - **Mitigation:** acceptable and *intended* — it's the microservice data
    boundary we want to demonstrate.
- `drizzle-orm/bun-sql` is newer than the node-postgres path.
  - **Mitigation:** golden rule #6 — verify on Bun in the compatibility spike
    (ADR-009) before relying on it; the node-`pg` driver is a fallback.
- Per-service migrations add operational steps.
  - **Mitigation:** `drizzle-kit` per service; each migration set lives with its
    service.

## Alternatives considered

- **Prisma** — great DX and types, but a heavyweight engine + generated client,
  historically rough Bun compatibility, and more magic than wanted for trivial
  data. Rejected.
- **Raw `Bun.sql` / hand-written SQL** — zero deps, but no schema types or
  migration tooling; we'd rebuild what Drizzle gives cheaply. Rejected.
- **Kysely** — excellent typed query builder, but Drizzle adds schema + migration
  tooling in one package and pairs idiomatically with Bun's SQL. Close call;
  Drizzle chosen for the integrated migration story.
- **Shared/single database for all services** — simplest operationally, but
  couples services through the schema and defeats the entire point of the
  exercise. Rejected.
