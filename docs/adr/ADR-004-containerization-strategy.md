# ADR-004: Containerization strategy

- **Status:** Accepted
- **Date:** 2026-06-10
- **Deciders:** project owner

## Context

Phase 1 packages every service as a container image (`docker compose up` first,
then the same images run on kind/Helm in Phase 2 — "same app runs at every
stage"). We need a consistent image strategy across all Bun services (ADR-001)
that is small, reproducible, secure, and unchanged as we move compose → K8s.

Concerns to settle once, for all services:

- **Base image** — what we build `FROM`.
- **Build shape** — single-stage vs multi-stage.
- **Runtime user** — root vs non-root.
- **Image size & attack surface** — fewer layers, no dev deps/toolchain in the
  final image.

## Decision

Standardize all service images on:

1. **Multi-stage Dockerfiles.** A `deps`/`build` stage installs dependencies and
   produces the runnable app; the final stage copies only what's needed to run.
   No source-only files, dev dependencies, or build tooling in the final image.
2. **`oven/bun` as the base** (ADR-001 runtime). Use the **slim** variant for the
   final stage; pin a specific version tag (not `latest`) for reproducibility.
3. **Run as a non-root user.** The final stage drops to an unprivileged user — a
   baseline for the Kubernetes `securityContext` work in Phase 2 and Kyverno
   policy (ADR-011).
4. **`.dockerignore`** in every service to keep build context minimal
   (`node_modules`, `.git`, local env, test output).
5. **One Dockerfile per service**, all following the same template, so per-service
   images stay independent (ADR-008) but consistent.

Distroless is noted as a **later hardening step**: `oven/bun` slim is the
pragmatic v1 base; revisit a distroless/minimal final stage once images and the
runtime footprint are understood (documented evolution, not v1 scope).

## Consequences

**Positive**

- Small, reproducible images; fast pulls and faster CI.
- Smaller attack surface (no toolchain/dev deps at runtime); non-root by default.
- Same image artifact flows compose → kind → managed unchanged.
- A single template keeps 5 services consistent and easy to reason about.

**Negative / risks**

- Multi-stage Dockerfiles are more involved than a single `FROM`.
  - **Mitigation:** one shared template; the complexity is paid once.
- Bun-on-container edge cases (native deps, lockfile install flags).
  - **Mitigation:** golden rule #6 — validated by the Bun compatibility spike
    (ADR-009) before relying on it.

## Alternatives considered

- **Single-stage image** — simplest, but ships dev deps + build tooling and is
  larger with a bigger attack surface. Rejected.
- **`node`-based image** — contradicts ADR-001 (Bun runtime). Rejected.
- **Distroless final stage from day one** — best attack surface, but more friction
  to get right initially (no shell for debugging, native-dep quirks). Deferred to
  a hardening step rather than v1.
