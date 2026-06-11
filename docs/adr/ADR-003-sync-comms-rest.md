# ADR-003: REST/JSON for synchronous communication (v1)

- **Status:** Accepted
- **Date:** 2026-06-10
- **Deciders:** project owner

## Context

vortex has two communication needs:

1. **Synchronous "need an answer now"** — client → `gateway`, and the internal
   `orders → inventory` stock check before confirming an order.
2. **Asynchronous "this happened, react whenever"** — `order.created` fanning out
   to `notifications` and `analytics` (handled separately by NATS/JetStream,
   ADR-006).

This ADR covers only the **synchronous** path. The candidates for v1 sync comms
are **REST/JSON** and **gRPC (via ConnectRPC/buf)**.

A core project rule is *design-first, evolve deliberately*: ship the simplest
thing that proves the concept, and treat later upgrades as documented evolution
rather than upfront complexity.

## Decision

Use **REST/JSON over HTTP** for all synchronous communication in v1 — both
client-facing (north-south) and internal service-to-service (east-west) sync
calls.

gRPC/ConnectRPC is **deferred** to a later phase as a documented evolution of the
*internal* sync path (see ADR-005), not removed from the roadmap.

## Consequences

**Positive**

- Simplest possible v1 — REST is already the owner's strength; zero new protocol
  friction while the focus is on infra (K8s, observability, GitOps).
- Trivially debuggable with `curl`, browsers, and standard tooling.
- Pairs directly with Hono (ADR-002); no codegen pipeline needed to start.
- Keeps the headline skills (Kubernetes, observability) unblocked.

**Negative / risks**

- No compile-time contract between services (REST/JSON is untyped on the wire).
  - **Mitigation:** this is exactly the gap the later gRPC/ConnectRPC evolution
    (ADR-005) is designed to close — typed protobuf contracts + polyglot codegen
    become a *visible senior decision* once the platform is in place.
- Slightly more boilerplate for request/response shapes vs generated clients.
  - **Mitigation:** shared TypeScript types in the monorepo (ADR-008) cover v1.

## Alternatives considered

- **gRPC / ConnectRPC from day one** — typed contracts and codegen are
  attractive, but add a buf/protobuf toolchain and complexity before the infra
  story (the actual product) is built. Deferred to ADR-005 as a later evolution.
- **GraphQL** — overkill for trivial dummy endpoints and a different paradigm
  than the sync RPC-style calls we want to demonstrate. Rejected.
