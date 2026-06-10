# CLAUDE.md — vortex

Guidance for Claude Code when working in this repository.

## What this project is

`vortex` is a **platform-engineering portfolio project**. The **infrastructure, system design, and engineering practices ARE the product** — the service business logic is intentionally trivial. Dummy endpoints exist only to demonstrate one infra/architecture concept each; never grow them into a real API.

**Goal:** prove zero→production end-to-end ownership and senior **judgment**. The two skills it is surgically built to demonstrate (the owner's CV gaps): **Kubernetes/orchestration** and **observability**.

**Core thesis:** in the AI era, boilerplate is cheap — the value is in *decisions*. So **decisions are first-class artifacts**: every meaningful choice gets an ADR. Judgment > typing.

> Full design rationale: `_bmad-output/brainstorming/brainstorming-session-2026-06-10-0050.md`

## Golden rules

1. **Design-first.** Before writing service/infra code, there must be an architecture diagram + the relevant `.proto` contract + an ADR. Cheap to change on paper.
2. **Decisions are documented.** Any non-trivial choice → `docs/adr/ADR-NNN-*.md`. Don't silently pick a library/pattern.
3. **Dummy endpoints with intent.** Each endpoint demonstrates exactly one concept (a gRPC call, a NATS event, `/healthz`+`/metrics`, one Postgres touch). No real business logic.
4. **Build infra once, in the right layer.** "Docker first" applies ONLY to the **app layer**. Platform-layer infra (observability, GitOps, OpenTofu) is built **after** Kubernetes — never twice.
5. **Same app runs at every stage.** Migrating the *same* services compose→kind→managed is the proof of mastery; do not rewrite services per stage.
6. **Verify Bun compatibility before adopting.** Bun has rough edges; spike risky deps first.

## Tech stack (chosen — see ADRs for why)

| Layer | Choice |
|---|---|
| Runtime | **Bun** (ADR-001) |
| HTTP framework | **Hono** (ADR-002) |
| API north-south (client) | **REST/JSON** (ADR-003) |
| API east-west (sync) | **gRPC via ConnectRPC/buf** — Connect protocol over HTTP/1.1, NOT pure-gRPC HTTP/2 (ADR-005) |
| Async events | **NATS + JetStream** (ADR-006) |
| Data | **Postgres + Drizzle** (`drizzle-orm/bun-sql`), **database-per-service** (ADR-007) |
| Repo | **Monorepo** — Turborepo + Bun workspaces, per-service deploys (ADR-008) |
| Containers | Multi-stage Dockerfiles, slim/distroless base (`oven/bun`), non-root |
| Orchestration | docker compose → **kind** (local K8s) → managed (stretch) |
| K8s packaging | raw YAML first (learn primitives) → **Helm** |
| GitOps | **ArgoCD** + Sealed Secrets |
| Observability | **LGTM** — Prometheus + Loki + Tempo + Grafana + **OpenTelemetry** (install via `kube-prometheus-stack` + loki/tempo/otel-collector charts). Fallback: SigNoz |
| IaC | **OpenTofu** (cloud only) — reusable `modules/` + remote state (ADR-010) |
| CI/CD | **GitHub Actions** (CI: lint/test/build/scan) + **ArgoCD** (CD). Monorepo-aware; `buf` proto lint + breaking-change check |
| Supply chain | Trivy scan + SBOM (Syft) + cosign signing → Kyverno "signed-only" (ADR-011, stretch) |
| Polyglot (stretch) | Go (`connect-go` + `nats.go`) + Rust (`tonic`/`axum` + `async-nats`) services sharing the same protobuf |

**Comms by intent:** REST = client-facing · gRPC = sync "need an answer now" · NATS = async "this happened, react whenever".

## Repo structure (target)

```
vortex/
├── docs/
│   ├── architecture.md          # system diagram + the "why"
│   └── adr/                      # ADR-001 … (decision records)
├── proto/                        # shared protobuf contracts (buf)
├── services/
│   ├── gateway/                  # Bun + Hono, REST → gRPC
│   ├── service-a/                # Bun + Hono, gRPC server + emits NATS
│   ├── service-b/                # Bun, consumes NATS
│   ├── service-go/               # (stretch) connect-go
│   └── service-rust/             # (stretch) tonic
├── deploy/
│   ├── compose/                  # Phase 1: docker-compose.yml
│   ├── k8s/                      # Phase 2: raw manifests
│   └── helm/                     # Phase 2: charts
├── platform/                     # Phase 3-4: ArgoCD apps, observability, sealed-secrets
├── infra/                        # cloud stretch: OpenTofu modules + environments
└── .github/workflows/            # CI
```

## Roadmap (each phase = a learning checkpoint, finished + understood before advancing)

- **Phase 0 — Design + spike:** architecture diagram + protos + ADRs; Bun compatibility spike (Hono+Connect+NATS+Drizzle).
- **Phase 1 — Docker app-layer:** dummy services + gRPC + 1 NATS flow + Postgres; multi-stage Dockerfiles + `docker compose up`; basic CI.
- **Phase 2 — Kubernetes (headline):** kind → raw YAML → Helm; k9s + Tilt for DX.
- **Phase 3 — Observability:** LGTM + OpenTelemetry; one trace REST→gRPC→NATS→consumer in Grafana.
- **Phase 4 — GitOps:** ArgoCD pulls from monorepo + Sealed Secrets.
- **Stretch (none block "done"):** polyglot Go/Rust · cloud + OpenTofu · cosign/SBOM enforcement · KEDA (scale on NATS lag) · Gateway API · service mesh.

## Conventions

- **TypeScript/Bun:** strict types; prefer interfaces; functional style; named exports. Run `bun run typecheck` (`tsc --noEmit`) before declaring done.
- **Filenames:** kebab-case.
- **Protobuf is the source of truth** for service contracts; generate clients, don't hand-write them. Lint with `buf`.
- **Secrets never committed** — Sealed Secrets / env, especially once GitOps is in.
- **Terraform/OpenTofu provisions cloud infra only** — apps are deployed via Helm/ArgoCD, never via `kubernetes_*` TF resources.

## Notes

- This repo also contains a generic React/Supabase rule file at `.claude/rules/best-practices.md` from a template — it does **not** describe vortex (vortex is a Bun/microservices/platform project). Treat *this* CLAUDE.md as authoritative for vortex.
