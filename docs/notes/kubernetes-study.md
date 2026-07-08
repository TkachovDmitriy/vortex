# Kubernetes (Phase 2) — theory through practice

The headline CV-gap skill. Built by hand on kind: full sync path
`host → Gateway → gateway → orders → inventory → Postgres` + async
`orders → NATS → notifications/analytics`. ADRs: 012 (Postgres), 013 (Gateway API), 014 (Helm).

---

## 1. Workloads — Deployment vs StatefulSet

- **Deployment** = stateless pods, interchangeable, ephemeral storage. Used for the 5 app services.
- **StatefulSet** = stable identity + persistent storage. Used for **Postgres** and **NATS**.
  - `volumeClaimTemplate` → each pod gets its own **PVC** that **survives restart/reschedule**.
  - **Stable identity** (`postgres-0`) re-binds the *same* PVC (`data-postgres-0`) on recreate.
  - Needs a **headless Service** (`clusterIP: None`) for stable per-pod DNS.
  - Storage **dynamically provisioned** via the default StorageClass (no hand-written PV).
- **Why:** a Deployment's pod has ephemeral storage → data lost on restart. A database needs StatefulSet.
- **Anchor:** Postgres = StatefulSet + volumeClaimTemplate + headless Service + `initdb.d`; NATS = StatefulSet + headless Service + JetStream persistence (`-js -sd /data`).

**Interview Qs:** Deployment vs StatefulSet? Why does a DB need a StatefulSet? What does the headless Service give you? → stable DNS identity for stateful pods.

---

## 2. Services & networking

- **ClusterIP** (default) — internal-only virtual IP + DNS; the 5 services + Postgres client access.
- **Headless** (`clusterIP: None`) — no virtual IP; DNS returns pod IPs directly (StatefulSet).
- **LoadBalancer** — external; used by the Gateway's data plane (Envoy proxy).
- **No Service at all** — the **NATS consumers** (`notifications`, `analytics`) have **no Service**: nothing connects *to* them; they **dial NATS outbound**. Readiness probe hits the pod directly.
- **Why:** Service type follows traffic direction. Consumers are pure clients → no Service needed.

**Interview Qs:** Service types? When would a workload have no Service? → outbound-only consumers.

---

## 3. Config & secrets

- **ConfigMap** = non-secret env/config. ⚠️ **Gotcha:** env from a ConfigMap is injected **only at pod start** — editing the ConfigMap does **not** update running pods → `kubectl rollout restart deploy/<x>`.
- **Secret** = credentials. **base64 = encoding, not encryption.** Real `*-secret.yaml` **gitignored**; `*-secret.example.yaml` committed to document the contract. Commit-safe answer = **Sealed Secrets** (Phase 4 / GitOps).
- **Anchor:** `orders` got `NATS_URL` via ConfigMap → needed `rollout restart` to take effect.

**Interview Qs:** ConfigMap vs Secret? Is a Secret encrypted? → no, base64; use Sealed Secrets / encryption-at-rest. Why didn't a config change take effect? → env applied only at pod start.

---

## 4. Init ordering — initdb vs initContainer (ADR-012)

- **One-time bootstrap** (create users/databases) → **`initdb.d`** script mounted via ConfigMap. Runs **once**, on Postgres's first init (empty data dir), as superuser.
- **Repeatable migrations + seed** → per-service **initContainer** (reuses the service image, `bun src/db/migrate.ts`). Runs on **every** pod start, **idempotent**, and **gates** the app container (no serving before schema exists).
- **Why split:** each mechanism matches its run-frequency (once vs every-start). initContainer gives an ordering guarantee a separate Job wouldn't.
- **database-per-service** (ADR-007) realised as separate DBs in one instance; boundary = **per-service least-privilege users** (`orders_app` owns only `orders`, `REVOKE CONNECT … FROM PUBLIC`). Blast radius contained.

**Interview Qs:** How to run DB migrations in k8s? → initContainer (gates app) or migration Job. One-time vs repeatable setup? initContainer vs a Job trade-off?

---

## 5. L7 entry — Gateway API, not Ingress (ADR-013)

- **Ingress** (`networking.k8s.io/v1`) = the classic L7 entry, but **feature-frozen** ("maintenance mode"); forces controller-specific behaviour into opaque **annotations**. The common `ingress-nginx` controller is **winding down** (2025 "IngressNightmare" CVEs).
- **Gateway API** = its GA successor (v1.0, late 2023). **Role-separated** typed resources:
  - **GatewayClass** — selects the controller (infra concern).
  - **Gateway** — the listener: port/protocol/host/TLS (operator concern).
  - **HTTPRoute** — path/host → backend Service (app concern).
- **Controller:** **Envoy Gateway** (Envoy = data plane under most service meshes → transferable).
- **Why:** greenfield 2026 project; building the frozen API sends the wrong signal. Gateway API = "I know the current landscape".
- **Anchor:** Gateway `:80` host `vortex.local` → HTTPRoute `/` → `gateway:3000`. Plaintext HTTP on kind; TLS (cert-manager + Let's Encrypt) deferred to cloud.

**Interview Qs:** Ingress vs Gateway API? Why is Ingress frozen? What are the 3 Gateway API resources and who owns each? Why Gateway API for a new cluster?

---

## 6. Helm packaging — umbrella + library chart (ADR-014)

- **Progression:** raw YAML first (learn primitives) → **Helm** (release lifecycle: `upgrade`/`rollback`/`uninstall`).
- **`common`** = `type: library` chart (renders nothing itself) exporting named templates (`common.deployment/service/configmap/labels`). Deployment is a **superset**: stable core + optional blocks gated by values (`{{- with .Values.initContainers }}`, `{{- if .Values.secret }}`). Variation lives 100% in each service's `values.yaml`.
- **`vortex`** = **services-only umbrella** depending on the 5 service charts → `helm install vortex` = one release. Data (Postgres/NATS) + platform (Gateway API) = **bootstrap infra applied separately** (not in the umbrella).
- **Discipline:** namespace-agnostic (no `namespace:` in templates; `-n vortex --create-namespace`); charts reference Secrets **by name only**, never template secret data; commit `Chart.lock`, gitignore vendored `charts/*.tgz`.

**Interview Qs:** Why Helm over `kubectl apply`? → release lifecycle. Library vs application chart? How do you DRY 5 near-identical services? Why keep secrets out of the chart?

---

## 7. Async — NATS + JetStream

- **NATS** = StatefulSet + headless Service; **JetStream** (`-js -sd /data`) persists streams on a PVC; monitoring/health on `:8222`.
- **Consumers** = Deployment **with no Service** (dial NATS outbound). One `POST /orders` → `order.created` → **both** `notifications` + `analytics` log the **same** orderId (fan-out).
- **Why:** REST = "need an answer now" (sync path); NATS = "this happened, react whenever" (async fan-out).

**Interview Qs:** Sync vs async comms — when each? How does one event reach multiple consumers? → pub/sub fan-out (JetStream durable consumers).

---

## 8. War stories (Phase 2 — real debugging)

1. **ConfigMap change had no effect** — env is injected only at pod start → `kubectl rollout restart`.
2. **kind LoadBalancer stuck `<pending>`** — kind has no cloud LB. Ran **`cloud-provider-kind`** on the host (gives the Envoy LB Service a routable Docker-net IP; cloud-portable, no recreate). MUST run with **`--gateway-channel disabled`** or it crashes installing pre-v1.5 Gateway-API CRDs that Envoy's `safe-upgrades` admission policy blocks.
3. **NixOS `/etc/hosts` read-only** → couldn't add `vortex.local` → tested with `curl --resolve vortex.local:80:<lb-ip>`.
4. **Editor mangled Helm templates** — Zed reformatted `{{- -}}` into invalid `{ { - } }` flow-maps on save → disable YAML format-on-save for `deploy/helm/`; validate with `helm template | yq`.
5. **StatefulSet PVC identity** — recreating `postgres-0` re-binds `data-postgres-0` (same data), unlike a Deployment which would lose it.

---

## Mental model to recite
```
stateless service  → Deployment + ClusterIP Service + ConfigMap + readiness probe
stateful (DB/NATS) → StatefulSet + volumeClaimTemplate(PVC) + headless Service
one-time setup      → initdb.d / initContainer;  migrations → initContainer (gates app)
external entry      → Gateway API (GatewayClass/Gateway/HTTPRoute) + Envoy Gateway
packaging           → Helm: library(common) + services-only umbrella; data/platform bootstrap
async               → NATS/JetStream; consumers = Deployment, no Service
secrets             → gitignored now → Sealed Secrets at GitOps
```
