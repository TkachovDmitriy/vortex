# ADR-015: Observability — metrics slice (kube-prometheus-stack + Operator CRDs)

- **Status:** Accepted (built + verified on kind 2026-06-24 — 5 targets UP, counters flowing, dashboard rendering)
- **Date:** 2026-06-23 (accepted 2026-06-24)
- **Deciders:** project owner

## Context

Phase 3 (Observability) is the project's **second CV-gap skill** — equal billing with
Kubernetes in the project's reason for existing, and currently at zero. The headline
goal is one distributed trace following `REST → orders → NATS → notifications/analytics`
in Grafana. That is the *end* state; this ADR scopes the **first slice: metrics**,
which is the safe minimum bar (metrics + a dashboard) and the foundation traces build on.

Current state of the app: every service already exposes a `/metrics` endpoint in valid
Prometheus exposition format (`text/plain; version=0.0.4`), via a **hand-rolled**
`src/lib/metrics.ts` (a `Map` of counters + a render function — no client library). The
endpoint comment explicitly defers "a real client" to "the Phase 3 observability
decision" — i.e. this ADR. So scrape *targets* already exist; the work is the
cluster-side pipeline plus deciding how rich app metrics should be.

The owner already knows the signal concepts (Prometheus pull, Loki push, Grafana) but
not the **Kubernetes-native** integration (the Operator pattern, ServiceMonitor/PodMonitor
CRDs). This ADR therefore commits to the K8s-native approach explicitly.

## Decision

**Install the metrics stack via `kube-prometheus-stack` into a dedicated `monitoring`
namespace; scrape app services with Operator CRDs (ServiceMonitor/PodMonitor); keep the
hand-rolled `metrics.ts` for this slice. Logs (Loki) and traces (Tempo) are later slices.**

1. **`kube-prometheus-stack` (one umbrella), not assembled standalone charts.** It bundles
   the **Prometheus Operator** + Prometheus + **Grafana** (Prometheus pre-wired as a
   datasource) + Alertmanager + `node-exporter` (node metrics) + `kube-state-metrics`
   (cluster object metrics) in one Helm release. Cluster-wide metrics work immediately,
   before touching app code. Installed via Helm (reuses ADR-014 skills) with a values file.

2. **Operator CRDs for scrape config — never a hand-edited `prometheus.yml`.** The
   Operator reconciles CRDs into Prometheus config:
   - **`ServiceMonitor`** for the Service-fronted services (`gateway`, `orders`,
     `inventory`) — selects their Services, scrapes port `metrics` / path `/metrics`.
   - **`PodMonitor`** for the NATS consumers (`notifications`, `analytics`) — they have
     **no Service** (ADR Phase 2), so scrape the pods directly.
   This is the declarative, GitOps-friendly, K8s-native pattern; pods churn and Prometheus
   auto-follows via K8s API service discovery.

3. **Keep hand-rolled `metrics.ts` for slice 1 — defer `prom-client`.** The existing
   custom module already emits valid Prometheus text, enough to get the pipeline green.
   Adopting a real client (`prom-client` for histograms/gauges/runtime metrics, or
   OTel-metrics to unify with later tracing) requires a **Bun-compatibility spike first**
   (golden rule #6) and would block the "get metrics flowing" milestone. Decision deferred
   to a focused follow-up once the pipeline works and latency histograms are actually needed.

4. **OOM / cardinality discipline lives in the chart values.** Prometheus memory ≈
   f(active series) = metric × label-value combinations. Set conservative **retention**
   (e.g. 7d), explicit **resource limits**, and a sized **PVC** in the values; avoid
   unbounded labels (no `order_id`/`pod`-as-label), and use ServiceMonitor `relabeling`
   to drop high-cardinality labels. (Translates the owner's existing OOM-avoidance instinct
   to K8s knobs.)

5. **Dedicated `monitoring` namespace; Grafana via port-forward for now.** Observability is
   platform infra (golden rule #4 — built after K8s, in its own layer), kept separate from
   the `vortex` app namespace and **not** part of the `vortex` app umbrella (it is
   bootstrap-style infra, like the data/platform layers). Grafana is reached via
   `kubectl port-forward` initially; exposing it through the Gateway (ADR-013) is deferred.

## Consequences

**Positive**

- Cluster-wide + app metrics with one Helm install; Grafana datasource pre-wired.
- Fully declarative scrape config (CRDs) — no hand-edited Prometheus config, GitOps-ready.
- Demonstrates the K8s-native observability pattern (Operator + ServiceMonitor/PodMonitor),
  the specific gap vs. the owner's existing VM-based Prometheus knowledge.
- No new app dependency now (hand-rolled metrics stay) — avoids a Bun-compat detour.
- Foundation in place for the Loki (logs) and Tempo (traces) slices that follow.

**Negative / risks**

- **Hand-rolled metrics are thin** — counters only, no latency histograms or runtime
  metrics. *Mitigation:* sufficient for slice 1; `prom-client`/OTel revisited next.
- **`kube-prometheus-stack` is heavy** on a kind cluster (several pods, Prometheus memory).
  *Mitigation:* conservative retention + resource limits in values (Decision §4).
- **PodMonitor for consumers** is slightly less common than ServiceMonitor. *Mitigation:*
  it's the correct tool for Service-less pods; good to learn explicitly.
- **CRD ordering** — ServiceMonitor/PodMonitor CRDs must exist (installed by the stack)
  before applying our monitors. *Mitigation:* install the stack first, then the monitors.

## Alternatives considered

- **Assemble standalone Prometheus + Grafana + Operator charts separately** — more control,
  but more wiring (datasource, RBAC) and no reason to when the community umbrella exists.
  Rejected for slice 1.
- **Adopt `prom-client` / OTel-metrics now** — richer metrics, but a Bun-compat spike that
  blocks the pipeline milestone (golden rule #6). Deferred, not rejected.
- **Push model (Pushgateway / remote_write)** — pull is correct for long-lived scrape
  targets (free target-health signal); push is for short-lived batch jobs, which these
  services are not. Rejected for app metrics.
- **Grafana Agent / Alloy-only (no full Prometheus)** — lighter, but the goal is to learn
  the canonical Prometheus-Operator path; revisit for resource-constrained cloud later.
- **Install into the `vortex` app namespace** — couples platform infra to the app; rejected
  for a dedicated `monitoring` namespace (standard separation).
