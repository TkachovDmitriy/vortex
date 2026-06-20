# deploy/k8s — raw Kubernetes manifests

Phase 2 manifests, applied to a local **kind** cluster. Hand-written raw YAML to
learn the primitives; these get packaged into a **Helm** chart in a later step
(the component-foldered layout below maps onto chart structure 1:1). See the
roadmap in `CLAUDE.md` and the decisions in `docs/adr/`.

## Layout — grouped by component, split by concern

```
deploy/k8s/
├── platform/                 # cluster-level, operator-owned
│   ├── namespace.yaml        #   the `vortex` namespace
│   └── gateway/              #   Gateway API L7 entry (ADR-013)
│       ├── gatewayclass.yaml #     GatewayClass → Envoy Gateway   (not yet written)
│       └── gateway.yaml      #     Gateway listener :80, host vortex.local
├── data/
│   └── postgres/             # stateful — its own lifecycle (ADR-012)
│       ├── statefulset.yaml
│       ├── service.yaml      #   headless Service (stable DNS)
│       ├── init-configmap.yaml   # initdb.d: creates per-service DBs + least-priv users
│       ├── secret.example.yaml   # committed template
│       └── secret.yaml           # real creds — GITIGNORED
└── services/                 # stateless apps, app-team-owned
    ├── gateway/              #   REST entry point
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── config.yaml
    │   └── httproute.yaml    #   HTTPRoute — lives WITH its app, not in platform/
    ├── orders/
    │   ├── deployment.yaml   #   + initContainer running drizzle migrate/seed
    │   ├── service.yaml
    │   ├── config.yaml
    │   ├── secret.example.yaml
    │   └── secret.yaml       #   GITIGNORED
    └── inventory/
        └── … (same shape as orders: deployment/service/config + secret.example.yaml + secret.yaml)
```

**Why this shape**

- **By component, never by resource type.** A service's files live together —
  you deploy and debug a service as a unit. Folders named `deployments/`,
  `services/` (by kind) scatter one service across many folders — an anti-pattern.
- **No filename prefix.** Inside `orders/` it's `deployment.yaml`, not
  `orders-deployment.yaml` — the folder already namespaces it. Mirrors a Helm
  chart's `templates/`.
- **Three concerns, three roots.** `platform/` (namespace, Gateway — operator
  lifecycle) · `data/` (stateful, distinct backup/HA lifecycle) · `services/`
  (stateless apps). This also mirrors **Gateway API's role split**: the `Gateway`
  listener is operator-owned (`platform/`), the `HTTPRoute` is app-owned
  (`services/<app>/`).
- **No Kustomize.** Raw YAML now → **Helm** later (the chosen templating/env tool,
  per `CLAUDE.md`). Inserting Kustomize between them is a third tool for no gain.

## Secrets

Real `secret.yaml` files hold credentials and are **gitignored**
(`deploy/k8s/**/secret.yaml`); only `secret.example.yaml` templates are committed.
Create a real one by copying its example and filling in values. Base64 is encoding,
not encryption — **Sealed Secrets** replaces this in the GitOps phase (Phase 4).

```bash
cp services/orders/secret.example.yaml services/orders/secret.yaml   # then edit
```

## Apply order

`kubectl apply -R` does not guarantee ordering, and some objects must exist before
others. Apply **platform → data → services**, and install the Gateway API CRDs +
Envoy Gateway controller **before** the `GatewayClass`/`Gateway`:

```bash
# 1. namespace first (everything else lives in it)
kubectl apply -f platform/namespace.yaml

# 2. Gateway API CRDs + Envoy Gateway controller (upstream install) — see ADR-013
#    (added when the gateway path is built)

# 3. platform Gateway resources
kubectl apply -R -f platform/

# 4. data, then services
kubectl apply -R -f data/
kubectl apply -R -f services/
```

Ordering is solved properly later by Helm hooks / ArgoCD sync waves; for raw YAML on
kind, apply the groups in the order above.

> **kind note:** external L7 entry needs the cluster created with
> `extraPortMappings` (80/443 → host). Verify, and recreate if missing, before
> installing the Gateway controller (ADR-013).
