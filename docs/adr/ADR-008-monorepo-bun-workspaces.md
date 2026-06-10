# ADR-008: Monorepo with Bun workspaces (Turborepo deferred)

- **Status:** Accepted
- **Date:** 2026-06-10
- **Deciders:** project owner

## Context

vortex has 5 services plus shared contracts. We must decide **where the code
lives** (repo layout) and **how multi-package tooling works**. Two axes are often
conflated and must be kept separate:

1. **Repo layout** — monorepo (one git repo) vs polyrepo (one repo per service).
2. **Runtime coupling** — independent services (own DB, own deploy, talk only
   over REST/NATS) vs coupled. This is orthogonal to repo layout: a monorepo does
   **not** make services coupled.

The classic reasons to choose **polyrepo** are organizational — separate teams,
access control, independent release cadences across a large org. None apply to a
solo learning/portfolio project; they would only add overhead (5–7 repos, an npm
publish/version dance for shared types, a fragmented demo).

A monorepo also has two tooling layers:

- **Package linking** — local cross-package imports without publishing. Built into
  Bun (`workspaces`).
- **Task orchestration / caching** — running build/test/typecheck across packages
  in dependency order, with caching. Provided by Turborepo (or Bun's built-in
  `--filter`).

## Decision

Use a **monorepo managed by Bun workspaces**, with services kept **strictly
independent** inside it.

- One git repo, one `bun install`, one lockfile.
- `services/*` and `packages/*` are Bun workspaces under the **`@vortex/*`** npm
  scope.
- Shared code lives in `packages/`:
  - `@vortex/shared-types` — request/response contracts shared by both ends of a
    REST call (the ADR-003 mitigation for untyped REST).
  - `@vortex/tsconfig` — one strict base `tsconfig` every package extends.
- Services communicate **only** over REST (ADR-003) / NATS (ADR-006). No service
  imports another service's internals; each owns its own Postgres DB (ADR-007),
  its own container, and its own deploy (per-service deploys).

**Turborepo is deferred.** Start with Bun's built-in `bun run --filter`. Adopt
Turborepo later — at the Phase 1 CI step — once build-time caching and an explicit
task graph actually pay off. That adoption will be recorded as a documented
evolution, not assumed up front.

## Consequences

**Positive**

- One clone → `docker compose up` runs the whole platform — the best possible
  reviewer experience.
- Shared contracts/protos are a local import (source of truth), no registry
  publishing or cross-repo version bumps.
- Atomic cross-service changes land in a single commit/PR.
- Still demonstrates true service independence (own DB, container, deploy) —
  proving the decoupling without the polyrepo tax.
- Minimal tooling to start (no Turbo config until it earns its place).

**Negative / risks**

- Monorepo discipline is on us: independence must be enforced by convention
  (no cross-service internal imports), since the repo boundary won't enforce it.
  - **Mitigation:** communicate only over REST/NATS; lint/review for cross-service
    imports.
- Bun `--filter` lacks caching/affected-only runs.
  - **Mitigation:** acceptable at 5 small services; revisit with Turborepo at CI.

## Alternatives considered

- **Polyrepo (one repo per service)** — stronger team/access isolation, but
  irrelevant for a solo project and worse on every axis that matters here (shared
  types, atomic changes, one-clone demo, CI multiplied 5–7×). Rejected.
- **Monorepo + Turborepo from day one** — caching is valuable, but adds config and
  a concept before build times justify it. Deferred (adopt at CI), not rejected.
- **Nx** — powerful, but heavier and more opinionated than needed for 5 Bun
  services; Bun workspaces + (later) Turborepo is lighter and more transparent.
  Rejected.
