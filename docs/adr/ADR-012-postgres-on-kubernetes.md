# ADR-012: Postgres on Kubernetes — StatefulSet + per-service least-privilege users

- **Status:** Accepted
- **Date:** 2026-06-18
- **Deciders:** project owner

## Context

Phase 2 moves the app onto Kubernetes (kind). The Postgres + database-per-service
decision (ADR-007) now needs a concrete K8s implementation. Stateful workloads
need different primitives than the stateless services (which are plain
Deployments + ClusterIP Services), and several coupled questions must be settled:

1. **How do you run a stateful database in K8s** so data survives pod
   restarts/rescheduling?
2. **How is database-per-service (ADR-007) realised** when running one Postgres
   in-cluster?
3. **How do services authenticate**, and how are credentials handled in git?
4. **Where do one-time bootstrap vs repeatable migrations run?**
5. **What is the HA scope** for this phase?

The data is deliberately trivial (golden rule #3); the point is to demonstrate
the **stateful K8s primitives and a defensible security boundary**, the same app
running compose → kind → managed.

## Decision

**Run Postgres as a StatefulSet with per-service least-privilege users; defer HA.**

1. **StatefulSet, not Deployment.** A `volumeClaimTemplate` gives the pod a
   persistent PVC that survives restarts, and stable identity (`postgres-0`)
   re-binds the *same* PVC (`data-postgres-0`) on every recreate. A **headless
   Service** (`clusterIP: None`) provides stable DNS. Storage is **dynamically
   provisioned** via kind's default StorageClass — no hand-written PV.

2. **One Postgres instance, multiple logical databases.** Database-per-service
   (ADR-007) is realised as separate databases (`orders`, `inventory`) in one
   instance for dev. The boundary is enforced by **users + grants**, not separate
   servers; physical/instance separation is a later/managed concern.

3. **Per-service least-privilege users.** Each service connects as its own user
   (`orders_app`, `inventory_app`), **owner of only its own database**, with
   `REVOKE CONNECT … FROM PUBLIC`. The superuser is admin-only. Blast radius: a
   compromised service cannot read another service's data.

4. **Bootstrap vs migrations are split by *when they run*.**
   - **User/database creation** → an `initdb.d` script (mounted via ConfigMap).
     Runs **once**, on Postgres's first init (empty data dir), as superuser.
   - **Schema migrations + seed** → a per-service **initContainer** (reusing the
     service image, `bun src/db/migrate.ts`). Runs on **every** pod start, is
     idempotent (`__drizzle_migrations`, upsert seeds), and **gates** the app
     container so it never serves before its schema exists.

5. **Secrets, not ConfigMaps, for credentials.** Real `*-secret.yaml` are
   **gitignored**; `*-secret.example.yaml` templates are committed to document the
   contract. Base64 is encoding, not encryption — **Sealed Secrets** is the
   commit-safe answer, deferred to the GitOps phase (Phase 4).

6. **HA/replication deferred.** Single-instance in-cluster Postgres for dev.
   A StatefulSet does **not** replicate data (each pod has an independent volume);
   production HA is an **operator** (CloudNativePG / Patroni) or a **managed
   service** (RDS / Cloud SQL) — a Phase B concern.

## Consequences

**Positive**

- Data persists across pod restart/reschedule (PVC), with the same app at every
  stage (extends ADR-007's portability into K8s).
- Least-privilege users contain blast radius and make the database-per-service
  boundary real, not just architectural.
- Reproducible: the whole stack rebuilds from committed manifests; migrations +
  seed re-run automatically via the initContainer (verified by cluster recreate).
- Clear separation of one-time bootstrap (`initdb.d`) from repeatable migrations
  (initContainer) — each in the mechanism whose run-frequency matches.

**Negative / risks**

- **Single instance = SPOF, no HA.** *Mitigation:* acceptable for dev/portfolio;
  HA deferred to an operator or managed DB in Phase B (documented above).
- **Secrets are only base64-encoded.** *Mitigation:* real secrets gitignored now;
  Sealed Secrets in Phase 4.
- **initContainer runs migrations on every pod start.** *Mitigation:* idempotent
  (migrations tracked, seeds upsert) — safe by design.
- **One instance shared by multiple databases** weakens isolation vs separate
  instances. *Mitigation:* per-service users + `REVOKE CONNECT FROM PUBLIC`;
  physical separation deferred to managed/cloud.

## Alternatives considered

- **Postgres as a Deployment** — pods have ephemeral storage; data is lost on
  every restart. Rejected — defeats the purpose of a database.
- **Managed DB (RDS / Cloud SQL) now** — correct for production, but Phase 2's
  goal is learning stateful K8s primitives by hand. Deferred to the cloud phase.
- **Postgres operator (CloudNativePG / Zalando-Patroni) now** — production-correct
  HA, failover, and primary-routing, but heavy for the learning goal; the value
  here is understanding the raw primitives first. Deferred to Phase B.
- **Shared superuser for all services** — simplest, but no least-privilege or
  blast-radius isolation. Rejected — the security boundary is the point.
- **Credentials in a ConfigMap** — wrong place for sensitive values. Rejected;
  Secrets used instead.
- **A separate migration Job instead of an initContainer** — valid and more
  decoupled, but the initContainer tightly *gates* the app (no serving before
  schema). Chosen for that ordering guarantee; a Job remains an option later.
