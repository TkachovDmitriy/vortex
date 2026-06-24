# ADR-016: Observability — logs slice (Loki + Grafana Alloy)

- **Status:** Accepted (built + verified on kind 2026-06-24 — Alloy tailing all pods, logs queryable in Grafana)
- **Date:** 2026-06-24
- **Deciders:** project owner

## Context

The metrics slice (ADR-015) is done — Prometheus + Grafana + dashboards on kind. The
observability work has three pillars: **metrics ✅, logs, traces.** This ADR scopes the
**logs slice**, the second pillar.

Rationale for sequencing logs *before* traces: for the project's DevOps-first career goal,
**metrics + logs is the credible baseline** (both are table-stakes for ops roles), whereas
distributed tracing is a strong *differentiator* but not table-stakes. Logs are also far
cheaper than tracing — **no application instrumentation** (services already log to stdout),
no Bun-compatibility spike, no cross-NATS context-propagation puzzle. So logs complete the
baseline at low cost; **tracing (OTel + Tempo) is explicitly deferred** to a later phase
(CLAUDE.md: "trace if time"), consistent with the roadmap rule "nothing removed, only
re-sequenced."

The owner already knows Loki conceptually (push model, vs Prometheus pull). The gap is the
**Kubernetes-native** integration: the DaemonSet-collector pattern and label-based indexing.

## Decision

**Install Loki (monolithic) + Grafana Alloy (collector) via Helm into the `monitoring`
namespace; surface logs in the existing Grafana via a sidecar-provisioned datasource.
Choose Alloy specifically so the deferred tracing slice is a drop-in, not a rewrite.**

1. **Loki, monolithic/single-binary mode, filesystem storage.** On kind the scalable and
   distributed Loki modes are overkill; monolithic is one pod with a filesystem-backed
   store — simplest, sufficient for a learning cluster. Object storage + scalable mode is
   a cloud-phase concern.

2. **Grafana Alloy as the collector — not Promtail.** A collector runs as a **DaemonSet**,
   tailing every pod's stdout/stderr off the node filesystem and **pushing** to Loki. Alloy
   is chosen over Promtail because:
   - Promtail is **deprecated** (Grafana, 2025) — building on it sends a dated signal.
   - **Alloy bundles OpenTelemetry Collector components.** The *same* Alloy that ships logs
     now can later **receive OTLP traces and export to Tempo** — so the deferred tracing
     slice drops onto the existing agent instead of requiring a separate OTel Collector.
     One collector, eventually all three signals. **This is the main reason for Alloy:**
     it makes postponing tracing free of rework.

3. **No application changes.** Alloy tails container stdout; the services already log to
   stdout (`order created`, etc.). The logs pillar requires zero app instrumentation —
   contrast with the tracing slice, which will.

4. **Loki indexes labels, not content (and cardinality is the failure mode).** Unlike ELK
   (full-text index of every line — powerful, heavy), Loki indexes a small label set
   (namespace/pod/container) and stores the body compressed ("grep at query time") — much
   cheaper. The discipline: **never promote high-cardinality fields (request-id, order-id)
   to Loki *labels*** — that explodes the index (same cardinality lesson as Prometheus).

5. **Surface in the existing Grafana via a datasource ConfigMap.** Reuse the
   kube-prometheus-stack Grafana sidecar: a ConfigMap labelled `grafana_datasource: "1"`
   pointing at the Loki service is auto-loaded. Logs then live in the **same Grafana** as
   metrics (Explore → LogQL) — one pane of glass, no second UI.

## Consequences

**Positive**

- Completes the metrics + logs baseline — the credible "I can do observability" claim for
  a DevOps role — cheaply and with no app changes.
- One Grafana for metrics + logs (and later traces); LogQL feels like PromQL.
- **Alloy is forward-compatible with the deferred tracing slice** — choosing it now means
  tracing is an enable-receiver + install-Tempo step later, not a collector swap.
- Demonstrates the K8s-native logging pattern (DaemonSet collector, label indexing) and
  current-tooling judgment (Alloy over deprecated Promtail).

**Negative / risks**

- **Alloy's config language is a learning curve** (Alloy/River syntax) vs Promtail's
  simpler YAML. *Mitigation:* the logs pipeline is small; the investment pays off when
  Alloy also handles traces.
- **Loki on kind adds memory pressure** on top of kube-prometheus-stack. *Mitigation:*
  monolithic mode + filesystem + short retention; tune limits in values.
- **Two more charts** (loki + alloy) to manage. *Mitigation:* same Helm pattern already
  established; acceptable.

## Alternatives considered

- **Promtail collector** — simpler config, huge doc corpus, but **deprecated** and
  **logs-only** (would need a separate OTel Collector for the deferred tracing). Rejected:
  Alloy is current and unifies logs + future traces.
- **`loki-stack` umbrella chart** — bundles Loki + Promtail in one install (convenient),
  but pins you to the deprecated Promtail. Rejected for the same reason.
- **ELK / EFK stack** — powerful full-text search, but redundant given the existing
  Grafana/Prometheus ecosystem, heavier to run, and a second UI. Worth knowing conceptually,
  not worth building here. Rejected.
- **Distributed/scalable Loki** — for production log volume; unnecessary on kind. Deferred
  to the cloud phase.
- **Building the tracing slice now instead** — the differentiator, but not table-stakes and
  the costliest pillar (app instrumentation + Bun spike). Deferred; Alloy keeps it cheap to
  add later.
