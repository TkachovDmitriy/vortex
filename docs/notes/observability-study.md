# Observability (Phase 3) — theory through practice

The 2nd CV-gap skill. Built by hand on kind, all in the `monitoring` namespace via Helm.
ADRs: 015 (metrics), 016 (logs). Tracing (OTel/Tempo) explicitly deferred.

---

## 0. The three pillars & sequencing

- **Metrics, logs, traces.** **metrics + logs = the credible baseline** (table-stakes for ops roles). **Tracing = differentiator**, not table-stakes, and the costliest (app instrumentation) → **deferred**.
- **Why this order:** logs before traces because logs need **zero app changes** (services already log to stdout), no Bun-compat spike, no context-propagation puzzle. Baseline cheaply, defer the expensive pillar.

---

## 1. Metrics — Prometheus (pull model) (ADR-015)

- **`kube-prometheus-stack`** (one Helm umbrella): **Prometheus Operator** + Prometheus + **Grafana** (datasource pre-wired) + Alertmanager + **node-exporter** (node metrics) + **kube-state-metrics** (cluster object metrics). Cluster-wide metrics work before touching app code.
- **Pull model:** Prometheus **scrapes** `/metrics` from targets (long-lived → free target-health signal). Contrast push (Loki).
- **Scrape config via Operator CRDs — never hand-edited `prometheus.yml`:**
  - **`ServiceMonitor`** — for Service-fronted services (`gateway`, `orders`, `inventory`).
  - **`PodMonitor`** — for the **Service-less** consumers (`notifications`, `analytics`) — scrape pods directly.
- **Cardinality = the failure mode.** Prometheus memory ≈ active series = metric × label-value combos. **Never** put high-cardinality values (`order_id`, `pod`) as labels → unbounded series → OOM.
- **Dashboards as-code:** ConfigMap labelled `grafana_dashboard: "1"` → Grafana sidecar auto-loads.
- **Anchor:** apps expose hand-rolled `/metrics` (counters); named chart port `http` so monitors reference it. All 5 `*_total` counters climb on `POST /orders`.

**Interview Qs:** Pull vs push — why is pull right for long-lived targets? What's the Operator/ServiceMonitor pattern? Why PodMonitor for some workloads? What causes Prometheus OOM? → cardinality.

---

## 2. Logs — Loki + Grafana Alloy (push model) (ADR-016)

- **Loki** = log store, **monolithic/single-binary + filesystem** on kind (object storage + scalable mode = cloud concern).
- **Collector = Grafana Alloy** as a **DaemonSet** — tails every pod's stdout/stderr off the node filesystem and **pushes** to Loki (`loki.source.kubernetes`).
- **Alloy over Promtail — deliberate:** (1) Promtail is **deprecated** (2025); (2) **Alloy bundles OpenTelemetry Collector components** → the *same* agent can later **receive OTLP traces → export to Tempo**. So deferring tracing costs **no rework** later — one collector, eventually all three signals. **This is the main reason for Alloy.**
- **Loki indexes labels, not content** (vs ELK full-text). Small label set (namespace/pod/container) + compressed body ("grep at query time") = cheap. **Same cardinality discipline** — never promote `request-id`/`order-id` to a Loki **label**.
- **One pane of glass:** surfaced in the existing Grafana via a datasource ConfigMap (`grafana_datasource: "1"`). Logs + metrics in the same Grafana; **LogQL** feels like PromQL. **Zero app changes.**

**Interview Qs:** Loki vs ELK? → label-index vs full-text; cheaper. Why Alloy over Promtail? → current + unifies future traces. Push vs pull for logs? Cardinality in Loki?

---

## 3. Tracing — deferred (know the plan)

- **Would be:** OTel SDK in the services + **Tempo** backend + the headline trace `REST → orders → NATS → notifications/analytics` in Grafana.
- **Why deferred:** the differentiator/stretch ("trace if time"), not offer-blocking; the **costliest** pillar (needs app instrumentation).
- **Hard parts when resumed:** (1) **Bun + `@opentelemetry/sdk-node` compat spike first** (golden rule #6); (2) **propagating trace context across the NATS async boundary** — inject/extract the trace context via **message headers** (auto HTTP propagation breaks at the async hop).
- Alloy (chosen in §2) makes it a **drop-in**: enable an OTLP receiver + install Tempo, no collector swap.

**Interview Qs:** What's distributed tracing / a span / trace context? Why is tracing harder than metrics/logs? → app instrumentation + context propagation, esp. across async (queue) boundaries.

---

## 4. Pull vs push (the through-line)

| | Model | Why |
|---|---|---|
| Prometheus (metrics) | **pull** (scrape) | long-lived targets → scraping gives free up/down health |
| Loki (logs) | **push** (Alloy → Loki) | logs originate on nodes; a DaemonSet collector ships them |

**Interview Q:** When pull, when push? → pull for long-lived scrapeable targets; push for log/event streams and short-lived jobs.

---

## 5. War stories (Phase 3 — real debugging)

1. **App ServiceMonitors silently ignored** — root cause: `serviceMonitorSelectorNilUsesHelmValues: false` was needed in kube-prometheus-stack values; without it the Operator ignores monitors outside its own release. **Silent** failure — targets just never appear.
2. **PodMonitor for Service-less consumers** — `notifications`/`analytics` have no Service, so ServiceMonitor can't select them → used **PodMonitor** to scrape pods directly.
3. **Control-plane targets DOWN on kind** (etcd/scheduler/controller-manager) — harmless: bound to `127.0.0.1` inside the kind node, not scrapeable. Not a real outage.
4. **Named ports matter** — had to name the chart port `http` so ServiceMonitor/PodMonitor could reference the port by name.
5. **Cardinality discipline** — kept `/metrics` counters low-cardinality (no `order_id` label) to avoid series explosion; same rule applies to Loki labels.

---

## Mental model to recite
```
stack        → kube-prometheus-stack (Operator + Prometheus + Grafana + exporters)
metrics      → PULL; scrape /metrics; ServiceMonitor (has Service) / PodMonitor (no Service)
logs         → PUSH; Loki + Alloy DaemonSet; label-index not full-text
collector    → Alloy (not Promtail) — bundles OTel → traces are a drop-in later
grafana      → one pane: PromQL (metrics) + LogQL (logs) + (future) traces
killer bug   → cardinality (high-cardinality labels → OOM / index blow-up)
tracing      → deferred: OTel + Tempo; hard part = context across NATS (header inject/extract)
```
