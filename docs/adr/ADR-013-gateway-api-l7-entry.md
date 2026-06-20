# ADR-013: Gateway API (not Ingress) for L7 cluster entry

- **Status:** Proposed
- **Date:** 2026-06-20
- **Deciders:** project owner

## Context

Phase 2 (Kubernetes) needs an external entry point so client traffic can reach the
`gateway` service from outside the cluster. The internal services are plain
Deployments + ClusterIP Services (ADR-012 for the stateful path) — reachable only
*inside* the cluster. Something must terminate north-south HTTP at the edge and
route it to the right Service.

The classic answer is the **Ingress API** (`networking.k8s.io/v1`) + an ingress
controller (commonly `ingress-nginx`). But the landscape has moved:

1. **The Ingress API is feature-frozen** ("maintenance mode"). It is stable and
   still supported, but no new features will be added. Its design forces
   controller-specific behaviour into opaque **annotations** (header routing,
   rewrites, canaries), with no separation between cluster-operator and app-team
   concerns.
2. **The Gateway API is its official successor** — GA (v1.0) since late 2023. It
   replaces annotation-soup with typed, role-separated resources and native
   support for header routing, traffic splitting, and cross-namespace routes.
3. **The community `ingress-nginx` controller is being wound down** — it hit
   serious CVEs in 2025 ("IngressNightmare") and its maintainers, short-staffed,
   have steered users toward Gateway API implementations.

vortex is a greenfield 2026 portfolio project whose explicit goal is demonstrating
**current platform judgment** on a CV-gap skill (Kubernetes / networking). Building
the frozen primitive would send the wrong signal; the defensible choice is the
successor. (This decision concerns **L7 entry only** — it does not touch the
internal ClusterIP/DNS service-to-service path.)

## Decision

**Use the Gateway API for L7 cluster entry, implemented by Envoy Gateway. Run
plaintext HTTP on kind; defer TLS to the cloud phase.**

1. **Gateway API over Ingress.** Model north-south routing with the three
   role-separated resources instead of a single annotation-laden `Ingress`:
   - **GatewayClass** — selects the controller implementation (infra concern).
   - **Gateway** — the listener: port, protocol, hostname, TLS (operator concern).
   - **HTTPRoute** — path/host routing rules to a backend Service (app concern).

   For Slice A: a `Gateway` listening on `:80` for host `vortex.local`, and an
   `HTTPRoute` mapping `/` → the `gateway` Service on port 3000.

2. **Envoy Gateway as the controller.** Conformant, single-manifest install, runs
   on kind, well-documented; Envoy is the data plane under most service meshes, so
   the knowledge transfers. (NGINX Gateway Fabric is the equivalent fallback if an
   nginx-based data plane is preferred.)

3. **Plaintext HTTP on kind; TLS deferred to cloud.** Local kind terminates plain
   HTTP — self-signed certs on a fake `vortex.local` demonstrate little and add
   trust-store friction. Production TLS termination at the Gateway via
   **cert-manager + Let's Encrypt** (needs a real public domain) is a **cloud-phase**
   concern, to be captured in its own ADR when built.

4. **kind plumbing.** The cluster must expose host ports 80/443 to the node via
   `extraPortMappings` so the controller's listener is reachable from the host.
   (Verify, and possibly recreate, the kind cluster before installing the controller.)

## Consequences

**Positive**

- Current, defensible architecture: the successor API, not the frozen one — the
  intended "I know the landscape" signal for interviews.
- Cleaner learning model for tutor mode: typed, role-separated fields instead of
  memorising controller-specific annotation strings.
- Native header routing / traffic splitting available later without annotation
  hacks (useful for canary/observability work in later phases).
- Avoids adopting `ingress-nginx`, a controller under active wind-down.

**Negative / risks**

- **Smaller corpus of StackOverflow/blog answers** than Ingress when debugging.
  *Mitigation:* Gateway API is GA and Envoy Gateway docs are strong; the concept
  set is small.
- **Most *existing* clusters/jobs still run Ingress today.** *Mitigation:* the
  Ingress concept was learned conceptually (what it is, why it's frozen) — enough
  to discuss in an interview without building the dead-end.
- **One more CRD set to install** vs Ingress (built into core). *Mitigation:*
  single-manifest install; trivial on kind.

## Alternatives considered

- **Ingress + ingress-nginx (the original plan)** — ubiquitous and familiar, but
  the API is frozen and this specific controller is being retired. Rejected for a
  greenfield 2026 project; the concept is still learned for discussion value.
- **Build Ingress now, migrate to Gateway API later (documented evolution)** —
  mirrors the REST→gRPC "later evolution" pattern and yields a migration artifact,
  but ~2× the work for marginal payoff. Rejected to spend that time reaching Phase 3
  observability (the other CV gap).
- **NGINX Gateway Fabric** — valid Gateway API implementation; kept as the fallback
  if an nginx data plane is preferred. Envoy Gateway chosen for transferability to
  service-mesh contexts.
- **NodePort / LoadBalancer Service for the gateway** — NodePort gives ugly ports
  and no host/path routing; LoadBalancer hangs `<pending>` on kind (no cloud LB
  provider). Both rejected as the front door; fine only as debug tools.
- **TLS on local kind now** — self-signed/local-CA certs demonstrate little and add
  friction. Deferred to the cloud phase where cert-manager + Let's Encrypt has a
  real story.
