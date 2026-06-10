---
stepsCompleted: [1, 2, 3, 4]
session_active: false
workflow_completed: true
ideas_generated: 22
inputDocuments: ['/home/td/projects/own-develop/cv-improve/cv.md']
session_topic: 'Platform engineering portfolio pet project — showcasing system design, DevOps, CI/CD, microservices (Docker→K8s), and declarative IaC (Terraform)'
session_goals: 'Showcase platform/system-design skills; practice new tools (Bun vs Node frameworks); make smart tooling decisions; define system + repo structure (dummy APIs are fine); LEARN incrementally — each phase is a self-contained learning milestone fully understood before advancing'
selected_approach: 'ai-recommended'
techniques_used: ['First Principles Thinking', 'Morphological Analysis', 'Resource Constraints']
ideas_generated: []
context_file: ''
---

# Brainstorming Session Results

**Facilitator:** dtkachov.codica
**Date:** 2026-06-10

## Session Overview

**Topic:** Platform engineering portfolio pet project — the infrastructure & engineering practices ARE the product, not the business logic.

**Goals:**
1. Showcase skills — system design, declarative IaC (Terraform modules), CI/CD pipelines, microservice architecture & orchestration
2. Practice new tools — explore the modern stack (Bun vs Node frameworks, etc.)
3. Make smart tooling decisions — runtime/framework, orchestration, IaC, observability
4. Define project structure — system topology + repo/service structure (APIs can be dummy stubs)
5. Learn incrementally — develop step-by-step where each phase is a self-contained learning milestone, fully understood before advancing (pedagogical clarity is a first-class goal)

**Key constraint:** "Start simple, evolve" arc — Docker first, Kubernetes later. Service logic is intentionally trivial. Each evolution step = a learning checkpoint.

**Positioning clarified:** NOT pursuing the "platform engineer" job title. Goal = grow as an engineer who owns products **zero → production end-to-end** (architecture + infra + devops). Core thesis: *AI now writes boilerplate, so the engineer's value moves up to judgment — architecture, tool research/selection, system design.* The project showcases DECISIONS, not typing.

## Technique Selection

**Approach:** AI-Recommended Techniques
**Recommended sequence:**
- **First Principles Thinking** — strip to bedrock: what must this project actually prove for the target?
- **Morphological Analysis** — systematically map every decision axis (runtime × framework × comms × orchestration × IaC × CI/CD × observability × repo strategy) and combinations.
- **Resource Constraints** — force an MVP + staged learning roadmap (v1 Docker → v2 K8s → v3 cloud/Terraform), each stage a learning checkpoint.

## Technique 1 — First Principles Thinking (Foundations)

> **[Foundation #1]: The Doubt-Killer Rubric**
> _Concept:_ The project's purpose is to neutralize the specific doubts an interviewer has after reading THIS CV (already strong backend+DevOps). Every feature justified by "which doubt does this kill?"
> _Novelty:_ Surgical, CV-aware targeting vs generic skill-showcasing.

> **[Foundation #2]: Kubernetes is the Headline, not a Footnote**
> _Concept:_ K8s is the single biggest CV gap (CV has Docker + serverless, no container orchestration). Docker v1 exists mainly to make the K8s migration a visible learning story.
> _Novelty:_ Reframes Docker→K8s arc as narrated proof of the one missing skill.

> **[Foundation #3]: Architecture & Decisions ARE the Product**
> _Concept:_ Since AI handles boilerplate, the deliverable is the reasoning — why this runtime/comms/orchestration. Repo surfaces decisions (ADRs, diagrams, tradeoff docs), not just code.
> _Novelty:_ Documented decision-making as a first-class artifact, matching post-AI reality where judgment > code.

> **[Foundation #4]: Zero-to-Production End-to-End Ownership**
> _Concept:_ Showcase the full vertical slice: design → services → containers → orchestration → IaC → CI/CD → observability, owned by one engineer. Trivial APIs are fine; the completeness of the production path is the proof.
> _Novelty:_ Demonstrates breadth + integration (the hard part) over isolated depth.

## Technique 2 — Morphological Analysis (Decision Grid)

### Decisions locked (with ADRs to write)

| Axis | Decision | Rationale (→ ADR) |
|---|---|---|
| Runtime | **Bun** | Most to learn, least CV redundancy; all-in-one toolchain. Tradeoff: fewer prod war-stories. |
| HTTP framework | **Hono** | Portable (Node/Bun/Deno/edge), transferable, hedges Bun bet, keeps runtime-agnostic story open. |
| API style | **Protocol-per-layer**: REST north-south, gRPC east-west | Right protocol per traffic direction; distributed-systems maturity signal. |
| gRPC impl | **ConnectRPC (buf)** over raw grpc-js | Multi-protocol, TS-native, Bun-friendly, schema linting + breaking-change detection. |

```
Client ──REST/JSON──► [API Gateway: Hono] ──gRPC (Connect)──► [internal services]
```

> **[Tooling #2 / ADR-001]: Bun runtime — learning bet** — pick the axis with most to learn, least CV overlap.
> **[Tooling #3 / ADR-002]: Hono framework** — portable, transferable, preserves orchestration narrative.
> **[Tooling #4 / ADR-003]: Protocol-per-layer (REST + gRPC)** — choose protocol by layer, not dogma.
> **[Tooling #5 / ADR-005]: ConnectRPC (buf)** — modern gRPC path; ecosystem research + contract governance signal.
> **[Tooling #6 / ADR-006]: NATS + JetStream** — async events on top of gRPC+REST; sync-vs-async judgment; cloud-native, pairs with K8s.
> **[Tooling #7 / ADR-007]: Drizzle + Postgres, database-per-service** — light typed layer; per-service DB boundary; data deliberately trivial.
> **[Tooling #8 / ADR-008]: Monorepo (Turborepo + Bun workspaces)** — shared proto/Helm/Terraform in one place; CI builds only changed services; per-service deploy independence.

> **[Tooling #9 / ADR-009]: Bun Compatibility Spike (task zero)** — throwaway proof that Hono+Connect+NATS+Drizzle all run on Bun BEFORE building. De-risks the new-toys bet; first commit; learning checkpoint #0.

### Bun compatibility verification
- **Hono** ✅ native · **Drizzle** ✅ (`drizzle-orm/bun-sql`) · **NATS** ✅ (official client, TCP via node compat)
- **ConnectRPC** ✅ — use **Connect protocol / gRPC-Web over HTTP/1.1** (NOT pure-gRPC HTTP/2, which Bun's server handles poorly). This is the real reason ConnectRPC > raw grpc-js for a Bun stack.

> **[Architecture #10]: Polyglot fleet (Bun + Go + Rust) — phase 2** — after Bun foundation works, add one Go (`connect-go` + `nats.go`) and one Rust (`tonic`/`axum` + `async-nats`) service, all sharing the SAME protobuf/Connect contracts + NATS events, each with its own multi-stage Dockerfile. Proves a language-agnostic platform, gives hands-on Go+Rust (Rust is a CV interest), stress-tests Docker/K8s, and demonstrates *the whole point of protobuf contracts*. Phase 2 so it never blocks v1.

### Three comms layers by intent
- **REST** (Hono gateway) — north-south, client-facing
- **gRPC / ConnectRPC** — east-west, synchronous "need an answer now"
- **NATS/JetStream** — async events, "this happened, react whenever"

### Containerization & Orchestration ladder
| Stage | Tool | Learn | Cost |
|---|---|---|---|
| v1 | `docker compose` | wiring, networks, env, volumes | free/local |
| v2a | **kind** (local K8s) | Deployments, Services, Ingress, ConfigMaps, Secrets | free/local |
| v2b | **Helm** | templating, releases | free |
| v3 (stretch) | managed K8s / k3s on Hetzner | LoadBalancer, real TLS | 💰 |
- **Containerization:** multi-stage Dockerfiles, `oven/bun` slim base, distroless where possible, non-root user, layer caching.
- **Same app runs at every stage** — the migration (compose→kind→managed) IS the proof of orchestration mastery.
- **Local K8s tool:** kind (CI/industry standard) — leaning this; k3d as lighter alt with k3s-on-VPS path.
- **Manifests → Helm:** write raw YAML primitives FIRST (understand them), then package with Helm.

### Modern K8s stack to learn (2026) — curated, not the whole zoo
1. **Core primitives** (raw YAML first): Pod/Deployment/ReplicaSet, Service, ConfigMap/Secret, Namespace, Ingress→Gateway API, PVC, HPA
2. **Local cluster:** kind (or k3d)
3. **Packaging:** Helm (core) + Kustomize (optional overlays)
4. **Networking:** ingress-nginx to start → **Gateway API** as the modern successor to Ingress (great ADR); service mesh (Linkerd/Cilium) = stretch
5. **Observability = LGTM stack** ⭐ (biggest CV doubt-killer): Prometheus + Grafana + Loki + Tempo + **OpenTelemetry**; install via `kube-prometheus-stack`
6. **GitOps:** **ArgoCD** ⭐ (or Flux) — cluster pulls from monorepo; top 2026 signal
7. **Secrets:** Sealed Secrets / External Secrets Operator (required once GitOps in)
8. **Autoscaling:** **KEDA** (scale on NATS queue lag — killer demo); Karpenter = cloud stretch
9. **Policy:** Kyverno (or OPA/Gatekeeper) — "no pod without resource limits" — stretch
10. **Dev experience:** **k9s** (TUI, daily driver), **Tilt/Skaffold** (auto rebuild→redeploy), stern (log tailing)
11. **CNI:** Cilium (eBPF) — advanced, skip unless going deep

**Suggested K8s learning order:** raw YAML primitives → ingress → Helm → observability (LGTM+OTel) → ArgoCD (GitOps) → Sealed Secrets → STRETCH (KEDA / Gateway API / Kyverno / mesh)

### IaC — OpenTofu (ADR-010)
- **OpenTofu** (open-source Terraform fork) — CV Terraform skills transfer 1:1, signals ecosystem awareness.
- **Boundary:** Terraform/OpenTofu provisions CLOUD infra (cluster, network, DNS, managed DB, IAM); apps deployed via Helm/ArgoCD — NOT via TF `kubernetes_deployment`.
- **Skill to show:** reusable `modules/` consumed by `environments/{dev,prod}` + **remote state** with locking (not local state).
- **Activates at v3 (cloud)** — phase-3 deliverable; already a CV strength so deepen the structure.

### CI/CD — GitHub Actions (CI) + ArgoCD (CD)
- **Modern split:** CI builds (push), GitOps deploys (pull). GH Actions: lint→test→build image→scan→push→bump manifest tag; ArgoCD syncs new tag to cluster.
- **Monorepo-aware:** build/test only changed services (Turborepo `affected` / path filters).
- **buf in CI:** protobuf lint + breaking-change detection (ties to ConnectRPC).
- **Trivy** container scanning.

> **[Tooling #11 / ADR-011]: Supply-chain security (SBOM + cosign + Trivy)** — CI generates SBOM (Syft), scans (Trivy), signs images keyless (cosign/Sigstore via GH OIDC); cluster enforces "signed images only" (Kyverno). Rare in portfolios; fills CV security gap; covers full lifecycle. Stretch/phase-3.

**Supply-chain explained:** SBOM = machine-readable "ingredients label" of every dep in an image (Syft generates, Trivy/Grype scan) → answer "am I affected?" instantly. cosign = cryptographic signature proving the image came from YOUR pipeline untampered (keyless via GH OIDC) → K8s policy refuses unsigned images.

## Final Stack (Morphological Analysis result)

| Layer | Choice |
|---|---|
| Runtime | Bun |
| Framework | Hono |
| API north-south | REST/JSON |
| API east-west (sync) | gRPC via ConnectRPC (Connect over HTTP/1.1) |
| Async events | NATS + JetStream |
| Data | Postgres + Drizzle, DB-per-service |
| Repo | Monorepo (Turborepo + Bun workspaces), per-service deploys |
| Containers | Multi-stage Dockerfiles, slim/distroless, non-root |
| Orchestration | docker compose → kind (local K8s) → managed (stretch) |
| K8s packaging | raw YAML → Helm |
| GitOps | ArgoCD |
| Observability | LGTM (Prometheus/Grafana/Loki/Tempo) + OpenTelemetry |
| IaC | OpenTofu (cloud only, phase 3+) |
| CI/CD | GitHub Actions (CI) + ArgoCD (CD) |
| Security | Trivy + SBOM (Syft) + cosign |
| Polyglot | + Go + Rust services (stretch) |

## Technique 3 — Resource Constraints (Roadmap)

**Constraint:** ~1–2 months, part-time (evenings/weekends) → MUST cut. Core = finishable; rest = honest stretch. Each phase is a learning checkpoint fully understood before advancing.

### Phase 0 — Foundation spike (a few evenings)
- Bun Compatibility Spike (Hono+Connect+NATS+Drizzle on Bun)
- Monorepo skeleton (Turborepo + Bun workspaces), buf/proto setup

### Phase 1 — "It runs on Docker" (weeks 1–2) — must-ship core
- 2 Bun+Hono services + REST gateway; gRPC (ConnectRPC) between them; 1 NATS event flow
- 1 service with Postgres + Drizzle; multi-stage Dockerfiles + `docker compose up`; basic GH Actions CI

### Phase 2 — "It runs on Kubernetes" (weeks 3–4) — THE headline / #1 doubt-killer
- kind cluster; raw YAML primitives FIRST (Deployment/Service/ConfigMap/Secret/Ingress); then Helm; k9s + Tilt DX

### Phase 3 — "I can see inside it" (week 5) — #2 doubt-killer
- kube-prometheus-stack (Prometheus+Grafana); OpenTelemetry traces + Loki logs; one real Grafana dashboard

### Phase 4 — "It deploys itself" (week 6) — top 2026 signal
- ArgoCD GitOps (cluster pulls from monorepo); Sealed Secrets
- ✅ End of week 6 = complete, impressive project killing every major doubt.

### Phases 5+ — Stretch (week 7–8 and beyond; pick by energy, none block "done")
- 🦀 Polyglot: Go (`connect-go`) + Rust (`tonic`) services — the "for me" learning reward
- ☁️ Cloud + OpenTofu: k3s on Hetzner / managed K8s, real TLS, remote-state modules
- 🔒 Supply-chain: SBOM (Syft) + cosign signing + Kyverno "signed-only" policy
- 📈 KEDA: autoscale a consumer on NATS queue lag

### Cut from 2-month core (correctly): Go/Rust, cloud, OpenTofu, cosign, KEDA, Gateway API, service mesh → all stretch. Ship Phases 0–4 complete & understood before any stretch. A finished 6-week project beats a half-built 6-month one.

### Monitoring detail (Phase 3)
- **LGTM stack** = the 2026 open-source standard: **Grafana** (dashboards) + **Prometheus** (metrics) + **Loki** (logs) + **Tempo** (traces) + **OpenTelemetry** (instrument once, send anywhere). Install via `kube-prometheus-stack`.
- **Modern alt:** **SigNoz** = OTel-native all-in-one (metrics+logs+traces in one app) — much less setup for solo; pragmatic shortcut. Grafana Cloud free tier = hosted but less learning.
- **Recommendation:** assemble LGTM yourself (more learning + signal); SigNoz as fallback. OpenTelemetry is the real transferable skill (vendor-neutral).
- **Killer demo:** one distributed trace REST → gRPC → NATS → consumer across polyglot services in Grafana/SigNoz.

### RECOMMENDED observability stack (final): Grafana LGTM
Three pillars + glue:
- **Metrics → Prometheus** · **Logs → Loki** · **Traces → Tempo** · **Dashboards → Grafana** (one pane for all three) · **Instrumentation → OpenTelemetry Collector + SDKs** · **Alerts → Alertmanager**
- Single-vendor (Grafana Labs) = clean integration; click slow trace → jump to its logs (the senior "correlated" demo).
- Install via Helm: `kube-prometheus-stack` (Prometheus+Grafana+Alertmanager) + `loki` + `tempo` + `opentelemetry-collector`.
- **OpenTelemetry is the #1 transferable skill** (vendor-neutral). Fallback if time-short: **SigNoz** (OTel-native all-in-one, single install).

### Sequencing refinement — "Docker first" is right ONLY for the app layer
Split infra into two buckets to avoid building things twice:
- **🟢 App-layer (portable, build on Docker first):** services, gRPC, NATS, Postgres, Dockerfiles, docker-compose, **basic CI** (lint/test/build/scan).
- **🔴 Platform-layer (K8s-native, build AFTER K8s — building on Docker = double work):** observability (LGTM, Helm install differs from compose), **GitOps/ArgoCD** (can't GitOps compose), **OpenTofu** (provisions cloud — nothing to do locally), KEDA, signed-image enforcement.

**Recommended order:**
0. **DESIGN FIRST** (a few hrs, paper) — architecture diagram + write `.proto` contracts + ADRs, committed BEFORE code. The senior "judgment" signal; AI can't do it for you. ← this is "spend more time on system design"
1. **Docker phase (app-layer)** — dummy services + gRPC + NATS + Postgres + Dockerfiles + compose + basic CI → "architecture works"
2. **K8s phase** — same services, no rewrite: kind → raw YAML → Helm → "runs on K8s" (migration = the proof)
3. **Platform-layer** — observability (LGTM+OTel) built once here + GitOps (ArgoCD) + Sealed Secrets
4. **Cloud stretch** — OpenTofu provisions real cluster + signed images + KEDA

**Dummy endpoints = infra demos with intent** (not real API): one gRPC call (sync), one endpoint emits NATS event→consumer (async), one `/healthz`+`/metrics` (observability), one Postgres touch (DB-per-service). That's ALL the business logic needed.

### AI-acceleration note (applies the user's own thesis)
- AI is FAST at: Phase 1 service boilerplate, Go/Rust dummy services (minutes), YAML/Helm/CI skeletons.
- AI is NOT fast at: K8s debugging (CrashLoopBackOff, ingress routing — operational, you debug), and understanding (if AI writes all infra and you don't read it → fail the interview "walk me through it").
- **Smart play:** let AI delete boilerplate cost, reinvest saved hours into infra learning (Phases 2–4) where learning + portfolio value live. Net: **polyglot Go/Rust likely promotes into the CORE** since AI makes those services nearly free and they strengthen the language-agnostic-platform story.

## Idea Organization and Prioritization

### Thematic Organization

**Theme 1 — Positioning & Strategy (the "why")**
- Doubt-killer rubric (target CV gap, not re-prove strengths)
- Architecture & decisions ARE the product (ADRs > code; post-AI thesis)
- Zero→production end-to-end ownership
- K8s + observability = the two biggest doubts to kill

**Theme 2 — Application Architecture (the "what runs")**
- Bun + Hono; REST (north-south) + gRPC/ConnectRPC (east-west) + NATS/JetStream (async)
- Postgres + Drizzle, DB-per-service; Monorepo (Turborepo + Bun workspaces)
- Tiny "infra-demo" endpoints with intent, not a real API
- Polyglot fleet (Go + Rust) — proves language-agnostic platform + validates protobuf

**Theme 3 — Platform & Operations (the "how it runs")**
- Containers → kind → Helm → managed cloud (stretch)
- LGTM observability (Prometheus/Loki/Tempo/Grafana + OpenTelemetry)
- GitOps with ArgoCD + Sealed Secrets
- OpenTofu (cloud infra, reusable modules + remote state)

**Theme 4 — Engineering Rigor (the "senior signals")**
- Bun compatibility spike before building
- CI/CD split (GH Actions builds, ArgoCD deploys), monorepo-aware
- Supply-chain security (SBOM + Trivy + cosign + Kyverno enforcement)
- Design-first: diagram + ADRs + proto contracts before code

### Prioritization Results (2-month part-time core)

| Priority | What | Why |
|---|---|---|
| P0 | Design-first + Bun spike | De-risk + judgment signal |
| P1 | Docker app-layer (services, gRPC, NATS, Postgres) | The architecture itself |
| P2 | Kubernetes (kind → Helm) | #1 doubt-killer (headline) |
| P3 | Observability (LGTM + OTel) | #2 doubt-killer |
| P4 | GitOps (ArgoCD) | Top 2026 signal |
| Stretch | Go/Rust · cloud+OpenTofu · cosign · KEDA | Bonus; none block "done" |

AI-shift: polyglot (Go/Rust) likely promotes into core since AI makes those dummy services nearly free.

### Action Planning — first week

1. **Name + repo:** init monorepo (`vortex`). Bun workspaces + Turborepo + buf.
2. **Design artifacts (commit first):** `docs/architecture.md` (system diagram + the why) + `docs/adr/` (ADR-001…011 — drafted in this session).
3. **Bun spike:** one Hono service proving Connect + NATS + Drizzle run on Bun. Green = proceed.
4. **First real slice:** gateway (REST) → service-A (gRPC) → emits NATS event → service-B reacts; `docker compose up`.

### Suggested repo structure
```
vortex/
├── docs/{architecture.md, adr/}
├── proto/                  # shared protobuf (buf)
├── services/{gateway, service-a, service-b, service-go*, service-rust*}
├── deploy/{compose, k8s, helm}
├── platform/              # ArgoCD apps, observability, sealed-secrets
├── infra/                 # OpenTofu modules + environments (cloud stretch)
└── .github/workflows/     # CI
```
(* = stretch)

### ADR backlog (write these — they ARE the portfolio)
- ADR-001 Bun runtime · ADR-002 Hono · ADR-003 protocol-per-layer · ADR-005 ConnectRPC
- ADR-006 NATS/JetStream · ADR-007 Drizzle + DB-per-service · ADR-008 monorepo
- ADR-009 Bun compatibility spike · ADR-010 OpenTofu · ADR-011 supply-chain (SBOM+cosign)

## Session Summary and Insights

### Key Achievements
- A complete, modern, senior-grade platform stack chosen with documented rationale per axis
- A finishable 2-month part-time roadmap split into learning checkpoints (design → Docker → K8s → observability → GitOps)
- Clear app-layer vs platform-layer split to avoid building infra twice
- Definitive observability recommendation (Grafana LGTM + OpenTelemetry)

### Key Insights
- The project's value is JUDGMENT (decisions/ADRs/system design), not boilerplate — matching the post-AI reality
- K8s and observability are the specific CV gaps; the project is surgically aimed at them
- protobuf/gRPC + NATS choices are retroactively validated by the polyglot (Go/Rust) plan
- "Docker first" is right only for the app layer; platform-layer infra belongs after K8s

### Session Reflections
Highly focused, decision-driven session. User drove tooling choices with strong instincts (learn-new over safe, questioned scope appropriately, caught the "don't build twice" point independently). Facilitation leaned on the CV to keep every choice tied to career ROI.
