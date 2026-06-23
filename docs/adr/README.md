# Architecture Decision Records

Each ADR records **one decision** — its context, the choice, the trade-offs
accepted, and the alternatives rejected. In vortex, **decisions are first-class
artifacts**: the ADRs are part of the product, not an afterthought.

## Conventions

- **Numbers are stable IDs**, assigned when a decision is made — never renumbered.
  Other docs link to a fixed `ADR-NNN`, so the number must not change.
- **Gaps are intentional.** A missing number means either "decided, not yet
  written" or a retired/unused slot — not a lost file.
- **Status** is one of: `Accepted` · `Proposed` · `Planned` (decided in the
  brainstorm, ADR not yet written) · `Superseded by ADR-NNN`.

## Index

| ADR | Decision | Status |
|---|---|---|
| [001](ADR-001-runtime-bun.md) | Bun as the runtime | ✅ Accepted |
| [002](ADR-002-http-framework-hono.md) | Hono as the HTTP framework | ✅ Accepted |
| [003](ADR-003-sync-comms-rest.md) | REST/JSON for synchronous comms (v1) | ✅ Accepted |
| [004](ADR-004-containerization-strategy.md) | Containerization strategy (multi-stage, non-root) | ✅ Accepted |
| 005 | gRPC via ConnectRPC — later evolution of internal sync | ⏳ Planned |
| [006](ADR-006-nats-jetstream-async-events.md) | NATS + JetStream for async events | ✅ Accepted |
| [007](ADR-007-postgres-drizzle-db-per-service.md) | Postgres + Drizzle, database-per-service | ✅ Accepted |
| [008](ADR-008-monorepo-bun-workspaces.md) | Monorepo with Bun workspaces (Turborepo deferred) | ✅ Accepted |
| 009 | Bun compatibility spike (task zero) | ⏳ Planned |
| 010 | OpenTofu for cloud IaC | ⏳ Planned |
| 011 | Supply-chain security (Trivy + SBOM + cosign) | ⏳ Planned |
| [012](ADR-012-postgres-on-kubernetes.md) | Postgres on K8s: StatefulSet + per-service least-privilege users | ✅ Accepted |
| [013](ADR-013-gateway-api-l7-entry.md) | Gateway API (not Ingress) for L7 entry — Envoy Gateway | ✅ Accepted |

> Numbering note: there is no ADR-004 gap anymore — it was an unassigned slot from
> the brainstorm (numbering jumped 003 → 005) and is now used for the
> containerization decision.
