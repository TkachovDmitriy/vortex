# ADR-002: Use Hono as the HTTP framework

- **Status:** Accepted
- **Date:** 2026-06-10
- **Deciders:** project owner

## Context

Every REST-facing service (`gateway`, `orders`, `inventory`) needs an HTTP
framework on top of Bun (ADR-001). Candidates: **Hono**, **Elysia**, the raw
**`Bun.serve`** API, or a classic like **Express**.

Priorities:

- **Runtime-agnostic** — the same app code should run on Bun now and survive a
  runtime change later without a rewrite (portability is part of the "same app
  runs at every stage" thesis).
- **Small, fast, modern** — middleware, typed routing, Web-standard
  `Request`/`Response`.
- **Good ergonomics** for `/healthz`, `/metrics`, JSON handlers, and middleware
  (logging, tracing later).

## Decision

Use **Hono** for all HTTP services.

Hono is a small, fast, Web-standard router that runs on Bun, Node, Deno,
Cloudflare Workers, etc. It has typed routing, a clean middleware model, and a
healthy plugin ecosystem — a good fit for thin, dummy-but-correct endpoints.

## Consequences

**Positive**

- Runtime portability — not locked to Bun's server API.
- Built on Web-standard `Request`/`Response` → idiomatic and future-proof.
- Lightweight; minimal overhead for many small services.
- Middleware model makes cross-cutting concerns (logging, OpenTelemetry tracing
  in Phase 3) clean to add later.

**Negative / risks**

- Smaller community than Express (but actively maintained and widely adopted in
  the Bun/edge ecosystem).
- Some Express-era middleware won't drop in directly — use Hono-native
  equivalents.

## Alternatives considered

- **`Bun.serve` (raw)** — zero deps, but we'd hand-roll routing/middleware and
  couple every service to Bun's API. Rejected for portability + ergonomics.
- **Elysia** — excellent Bun-native DX and performance, but tightly coupled to
  Bun. Rejected to keep runtime portability (ADR-001 risk mitigation).
- **Express** — most familiar, but heavier, callback-era API, not built on Web
  standards. Rejected as dated for a 2026 portfolio.
