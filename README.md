# 🌀 vortex

> A platform-engineering playground where the **infrastructure, system design, and engineering practices are the product** — not the business logic.

`vortex` is a microservices platform built to demonstrate **end-to-end ownership from zero to production**: system design → services → containers → orchestration → observability → GitOps → IaC. The service endpoints are intentionally trivial; each one exists to showcase exactly one infrastructure or architecture concept.

> **Status:** 🚧 In active development — built incrementally, one learning checkpoint at a time. See the [roadmap](#-roadmap).

---

## Why this project exists

In the AI era, boilerplate is cheap — **engineering value lives in judgment**: choosing the right tools, designing for failure, and reasoning about tradeoffs. So in this repo, **decisions are first-class artifacts** — every meaningful choice is documented as an [ADR](docs/adr/).

The goal is to demonstrate, end to end:
- **System design** — protocol-per-layer comms, sync vs async, database-per-service
- **Containerization & orchestration** — Docker → Kubernetes
- **Observability** — metrics, logs, and distributed tracing
- **GitOps & CI/CD** — automated, declarative delivery
- **Infrastructure as Code** — reusable, declarative modules

---

## Architecture

```
            ┌──────────────┐
  client ── REST/JSON ────► │   Gateway    │  (Bun + Hono)
            └──────┬───────┘
                   │ gRPC (ConnectRPC)         ┌───────────┐
                   ├──────────────────────────►│ service-a │ ──┐
                   │                            └───────────┘   │ emits
                   │                                            ▼
                   │                                     ┌─────────────┐
                   │                                     │ NATS/JetStream │ (async events)
                   │                                     └──────┬──────┘
                   │                            ┌───────────┐   │ reacts
                   └───────────────────────────│ service-b │◄──┘
                                                └───────────┘
```

**Communication by intent:**
- **REST** — client-facing (north-south)
- **gRPC / ConnectRPC** — synchronous service-to-service ("need an answer now")
- **NATS / JetStream** — asynchronous events ("this happened, react whenever")

---

## Tech stack

| Layer | Choice | Why ([ADR](docs/adr/)) |
|---|---|---|
| Runtime | **Bun** | Modern all-in-one toolchain |
| HTTP framework | **Hono** | Portable, fast, runtime-agnostic |
| Sync comms | **gRPC via ConnectRPC** | Typed contracts, HTTP/1.1-friendly on Bun |
| Async comms | **NATS + JetStream** | Lightweight, cloud-native event streaming |
| Data | **Postgres + Drizzle** | Database-per-service, light typed layer |
| Repo | **Monorepo** (Turborepo + Bun workspaces) | Shared proto contracts, per-service deploys |
| Containers | **Docker** (multi-stage, non-root) | Reproducible builds |
| Orchestration | **Kubernetes** (kind → Helm → managed) | The headline skill |
| GitOps | **ArgoCD** + Sealed Secrets | Declarative, git-as-source-of-truth delivery |
| Observability | **Grafana LGTM** (Prometheus / Loki / Tempo) + **OpenTelemetry** | Metrics, logs, traces |
| IaC | **OpenTofu** | Reusable modules + remote state |
| CI/CD | **GitHub Actions** + ArgoCD | Build/test/scan, then GitOps deploy |
| Supply chain | **Trivy + SBOM + cosign** | Image scanning & signing |
| Polyglot (stretch) | **Go** (`connect-go`) + **Rust** (`tonic`) | Proves a language-agnostic platform |

---

## Roadmap

Each phase is a self-contained learning checkpoint — finished and understood before advancing.

- [ ] **Phase 0 — Design & spike:** architecture diagram, protobuf contracts, ADRs, Bun compatibility spike
- [ ] **Phase 1 — Docker:** services + gRPC + NATS + Postgres, multi-stage Dockerfiles, `docker compose up`, basic CI
- [ ] **Phase 2 — Kubernetes:** kind cluster, raw manifests → Helm
- [ ] **Phase 3 — Observability:** LGTM stack + OpenTelemetry tracing
- [ ] **Phase 4 — GitOps:** ArgoCD + Sealed Secrets
- [ ] **Stretch:** polyglot Go/Rust services · cloud + OpenTofu · cosign/SBOM enforcement · KEDA autoscaling

---

## Repository structure

```
vortex/
├── docs/
│   ├── architecture.md     # system diagram + the "why"
│   └── adr/                # Architecture Decision Records
├── proto/                  # shared protobuf contracts (buf)
├── services/               # gateway, service-a, service-b (+ Go/Rust, stretch)
├── deploy/                 # compose / k8s manifests / helm charts
├── platform/               # ArgoCD apps, observability, sealed-secrets
├── infra/                  # OpenTofu modules + environments
└── .github/workflows/      # CI
```

---

## Getting started

> Prerequisites and run instructions will be added as Phase 1 lands.

```bash
# clone
git clone git@github.com:TkachovDmitriy/vortex.git
cd vortex

# (Phase 1) run the stack locally
docker compose -f deploy/compose/docker-compose.yml up
```

---

## License

MIT
