# ADR-013: Gateway API (not Ingress) for L7 cluster entry

- **Status:** Accepted
- **Date:** 2026-06-20 (accepted 2026-06-21, after building + verifying on kind)
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

4. **kind plumbing — `cloud-provider-kind`, not `extraPortMappings`.** Envoy
   Gateway exposes its proxy through a `LoadBalancer` Service, which kind leaves
   `<pending>` (no cloud LB). Rather than recreate the cluster with
   `extraPortMappings` + a NodePort hack (kind-only, non-transferable), run
   **`cloud-provider-kind`** on the host: it watches `LoadBalancer` Services and
   assigns them a routable Docker-network IP — the same semantics a real cloud LB
   provides, so the `Gateway`/`HTTPRoute` YAML stays cloud-portable with **no
   recreate needed**. Run it with **`--gateway-channel disabled`**: its redundant
   Gateway-API CRD installer ships pre-v1.5 CRDs that Gateway API v1.5's
   `safe-upgrades` ValidatingAdmissionPolicy (bundled by Envoy Gateway) correctly
   blocks; we only need its LoadBalancer support, so the channel is turned off.
   The assigned IP is RFC1918-private (host-reachable only); test with
   `curl --resolve vortex.local:80:<ip>` (NixOS `/etc/hosts` is read-only). On a
   real cloud the identical manifests get a **public** LB IP instead.

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
- **Exposing the `gateway` Service directly via NodePort/LoadBalancer** (no Gateway
  API) — NodePort gives ugly ports and no host/path routing; a bare LoadBalancer
  has no L7 routing. Rejected as the front door — we want Gateway API semantics.
  (Note: the *Gateway's* data-plane Service is itself a LoadBalancer, made routable
  on kind by `cloud-provider-kind` — see Decision §4. That's different from
  exposing the app Service directly.)
- **`extraPortMappings` + NodePort to reach the Gateway on kind** — the classic
  ingress-on-kind recipe, but requires recreating the cluster and pins the proxy to
  a NodePort: kind-only plumbing that doesn't transfer to cloud. Rejected in favour
  of `cloud-provider-kind`, which mirrors real cloud LB semantics (Decision §4).
- **TLS on local kind now** — self-signed/local-CA certs demonstrate little and add
  friction. Deferred to the cloud phase where cert-manager + Let's Encrypt has a
  real story.
