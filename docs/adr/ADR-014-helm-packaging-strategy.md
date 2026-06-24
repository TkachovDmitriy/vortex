# ADR-014: Helm packaging — umbrella + shared library chart

- **Status:** Accepted
- **Date:** 2026-06-23 (accepted after building + rendering all 5 services + umbrella on Helm 4.2.0)
- **Deciders:** project owner

## Context

Phase 2 raw manifests in `deploy/k8s/{services,data,platform}/` were built first to
learn the primitives (the roadmap's "raw YAML → Helm" progression). They work, but
as a *deploy mechanism* they have two problems the portfolio needs to outgrow:

1. **No release lifecycle.** `kubectl apply -f` has no concept of a release — no
   `upgrade`, `rollback`, or `uninstall` over a tracked set of objects. Helm adds
   exactly that.
2. **Duplication.** The five app services (`gateway`, `orders`, `inventory`,
   `notifications`, `analytics`) share ~90% of their Deployment/Service/ConfigMap
   shape; they differ only in name, image, port, and which optional pieces they
   carry (Service yes/no, Secret ref yes/no, migrate initContainer yes/no). Raw
   YAML copy-pastes that shape five times.

The five services split cleanly into a stable core plus a few optional blocks, which
makes them a natural fit for a **shared library chart**. The data layer (Postgres +
NATS StatefulSets) and platform layer (Gateway API resources) do **not** share that
shape — they are bespoke singletons.

This ADR records how vortex is packaged with Helm and where the boundaries sit.

## Decision

**Package the five app services with an umbrella chart over a shared library chart,
laid out as flat siblings. Helm becomes the single source of truth for app
deployment; `deploy/k8s/` is frozen as a learning reference.**

1. **Umbrella + shared library, not single-umbrella or copy-paste.**
   - **`common`** — a `type: library` chart that renders nothing itself and exports
     named templates: `common.deployment`, `common.service`, `common.configmap`,
     `common.labels`, `common.selectorLabels`. The Deployment is a **superset**:
     a stable explicit core (image/port/replicas/probe) plus optional blocks gated
     by values — `{{- with .Values.initContainers }}` (toYaml passthrough, handles
     0..N init containers), `{{- if .Values.secret }}` (secretRef), and the Service
     via its own template. Variation lives 100% in each service's `values.yaml`.
   - Each **service chart** is thin: `Chart.yaml` + `values.yaml` + one-line
     templates (`{{- include "common.deployment" . -}}`, etc.).
   - **`vortex`** — the umbrella; depends on the five service charts so
     `helm install vortex` brings the app layer up as one release.

2. **Flat sibling layout** under `deploy/helm/` (`common/`, the 5 services, `vortex/`
   as top-level siblings) — *not* nesting the sources inside `vortex/charts/`. This
   keeps `common` a standalone directory that is easy to extract/publish, and lets
   any service chart be installed independently (honors ADR-008 per-service deploys).
   Helm's `dependency update` vendors deps into each chart's `charts/` as `.tgz`.

3. **`common` wired via `file://../common` now; OCI-published as the evolution.**
   Local path reuse works within this repo today. Cross-project reuse (a second
   consumer) graduates `common` to a versioned **OCI artifact**
   (`helm push … oci://ghcr.io/<org>/charts`), consumed by version — the same model
   Bitnami's `common` library uses. Only the `repository:` line changes; contents
   and `include` sites stay identical. (Mirrors the REST→gRPC "later evolution"
   pattern of ADR-005.)

4. **Library covers the 5 app services only.** Postgres/NATS (StatefulSets) and the
   Gateway API resources (GatewayClass/Gateway/HTTPRoute) are **not** forced through
   `common` — different shapes, forcing them in would be over-abstraction.

5. **Services-only umbrella (option a).** `vortex` manages the five app services.
   The **data** layer (Postgres/NATS) and **platform** layer (Gateway API) are
   *bootstrap infra* applied separately (raw `kubectl apply`), not subcharts of the
   umbrella. They are stable, cluster-scoped, and rarely change; coupling them into
   the app release would muddy the lifecycle. (A full-stack umbrella remains a
   possible later evolution.)

6. **Charts are namespace-agnostic; namespace is supplied at install time.** No
   `namespace:` field in any template. `helm install … -n vortex --create-namespace`
   sets the release namespace; Helm applies every resource into that namespace via
   the API context. Where a namespace value is genuinely needed in a template, use
   `{{ .Release.Namespace }}`, never a literal. Consequence: the standalone
   `platform/namespace.yaml` is obsolete (`--create-namespace` replaces it).

7. **Charts reference Secrets by name, never template Secret contents.** The
   Deployment carries a `secretRef: { name: <svc>-secret }` (gated by `secret: true`
   in values) but the chart never renders a `kind: Secret` — that would put
   credentials in git, violating the "secrets never committed" rule. The Secret is
   provisioned **out-of-band**: a gitignored manifest applied with `kubectl` **now**,
   produced by **Sealed Secrets** at the GitOps phase. App chart = wiring; secret
   lifecycle = separate concern.

8. **Standard recommended labels.** `common.labels` emits the full
   `app.kubernetes.io/*` set; `common.selectorLabels` emits only the immutable
   subset (`name` + `instance`) — `version` is deliberately excluded from selectors
   (selectors are immutable; a per-release label there makes a Deployment
   un-upgradeable). The version label is kept for observability (group metrics by
   version) — one of the project's two CV-gap skills.

9. **Vendored `.tgz` gitignored; `Chart.lock` committed.** Treat `charts/*.tgz` like
   `node_modules` (regenerable via `helm dependency build`) and `Chart.lock` like
   `package-lock.json` (the reproducible pin). Commit the lock, ignore the tarballs.

10. **`deploy/helm/` is the single source of truth; `deploy/k8s/` is frozen.** Apps
    deploy via Helm. The raw manifests are retained as a learning/reference artifact
    documenting the raw→Helm progression, marked as not maintained — not a second
    live deploy path.

## Consequences

**Positive**

- DRY: the Deployment/Service/ConfigMap shape is authored once in `common`; adding
  or changing a service is a values edit, not a template copy. Demonstrated — a
  correct second service (`notifications`) came from a values file alone.
- Real lifecycle: `helm upgrade`/`rollback`/`uninstall` over the whole release.
- One-command app stack (`helm install vortex`) while each service stays
  independently installable.
- `common` is a genuinely portable package — one `helm push` from cross-project reuse.
- Clean separation of concerns: app charts (wiring) vs secrets (out-of-band) vs
  data/platform (bootstrap).

**Negative / risks**

- **Indirection.** Reading `gateway/templates/deployment.yaml` (a one-line include)
  doesn't show the rendered shape; you must read `common`. *Mitigation:*
  `helm template <svc>` is the source of truth; render-after-change is the workflow.
- **Whitespace/templating fragility** (`nindent`, `{{- -}}`, brace spacing). Editors
  without Helm awareness re-format `{{- -}}` into invalid flow-maps. *Mitigation:*
  `helm lint` + `helm template | yq` as the real linter; disable YAML format-on-save
  for `deploy/helm/`.
- **Bootstrap split is not "one command for everything."** Data/platform must be
  applied before `helm install vortex`. *Mitigation:* documented; acceptable for
  stable infra; foldable into the umbrella later if desired.

## Alternatives considered

- **Single umbrella chart** (all 5 services rendered from one `values.yaml` via
  `range`) — simplest, but no per-service independent install and far less
  library-chart depth (a headline learning goal). Rejected.
- **Chart-per-service with no sharing** — five standalone charts copy-pasting
  near-identical templates: the exact duplication Helm libraries exist to remove.
  Rejected.
- **`common` nested under `vortex/charts/`** — works, but buries the library and
  makes cross-project extraction awkward. Rejected in favour of flat siblings.
- **Full-stack umbrella (option b)** — also chart Postgres/NATS/Gateway API for a
  true single-command stack. More work; those StatefulSets/singletons gain nothing
  from `common`. Deferred as a possible evolution; services-only chosen now.
- **Templating Secrets from values (`-f secrets.yaml`/`--set`)** — keeps the secret
  out of committed values but is one mistake from leaking and couples secret
  lifecycle to the chart. Rejected for reference-only + out-of-band provisioning.
- **Hardcoding `namespace: vortex` in templates** — locks charts to one namespace
  and can fight Helm's release namespace. Rejected for namespace-agnostic charts.
- **Keeping raw `kubectl apply` as the deploy mechanism** — no release lifecycle and
  the duplication problem stands. Rejected; raw kept as frozen reference only.
