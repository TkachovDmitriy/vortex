# ADR-001: Use Bun as the runtime

- **Status:** Accepted
- **Date:** 2026-06-10
- **Deciders:** project owner

## Context

vortex is composed of several small TypeScript microservices. We need a
JavaScript/TypeScript runtime + toolchain. The realistic options in 2026 are
**Node.js**, **Deno**, and **Bun**.

Priorities for this project:

- **One toolchain, low ceremony** — many small services means setup cost is paid
  repeatedly; fewer moving parts (no separate `tsc` / test runner / bundler /
  package manager) is a real win.
- **Native TypeScript** — run `.ts` directly without a build step in dev.
- **Fast cold start + install** — lots of containers, frequent CI builds.
- **Learning value** — this is a portfolio project; a modern runtime is part of
  the story.

## Decision

Use **Bun** as the runtime and toolchain across all services.

Bun bundles the runtime, package manager, test runner, and bundler into a single
binary, runs TypeScript natively, and has fast installs and cold starts — all of
which suit a many-small-services monorepo.

## Consequences

**Positive**

- One tool replaces `node` + `npm` + `tsc` + `jest` + a bundler.
- Native TS execution → simpler dev loop, simpler Dockerfiles.
- Fast `bun install` and startup → quicker CI and container boots.
- First-class workspaces support pairs well with the monorepo (see ADR-008).

**Negative / risks**

- Younger ecosystem than Node — some npm packages have rough edges on Bun.
  - **Mitigation:** golden rule #6 — spike risky dependencies (NATS client,
    Drizzle, ConnectRPC) on Bun *before* adopting them.
- Fewer "battle-tested in prod at scale" references than Node.
  - **Mitigation:** acceptable for a portfolio/learning project; the container
    image is `oven/bun`, and services are stateless and replaceable.

## Alternatives considered

- **Node.js** — safest, largest ecosystem, but multi-tool setup
  (node+npm+tsc+test runner+bundler) and slower DX. Rejected for ceremony.
- **Deno** — excellent DX and security model, native TS, but smaller npm
  compatibility surface and a different module story. Rejected to keep the npm
  ecosystem fully available.
