# ADR-006: NATS + JetStream for asynchronous events

- **Status:** Accepted
- **Date:** 2026-06-13
- **Deciders:** project owner

## Context

The synchronous path is REST (ADR-003): the caller needs an answer now
(`orders → inventory`). The other half of the architecture is **asynchronous**:
`orders` announces "an order was created" and unrelated services
(`notifications`, `analytics`) react whenever — no reply expected, and new
reactors can be added without touching the producer.

This needs a messaging system with:

- **Pub/sub fan-out** — one event delivered to multiple independent consumers.
- **Durability / at-least-once** — a consumer that is down must receive missed
  events when it returns (not fire-and-forget that drops messages).
- **Cloud-native fit** — lightweight, runs trivially in compose and on K8s
  (pairs with the headline orchestration story; KEDA can later scale on lag).
- **Bun compatibility** (golden rule #6).

## Decision

Use **NATS with JetStream** as the async backbone.

- **Stream `ORDERS`** captures subjects `order.>`; the producer (`orders`) owns
  it and ensures it exists on startup (`ensureOrderStream`, idempotent).
- **Subject `order.created`** carries the `OrderCreatedEvent` contract
  (`@vortex/shared-types`), JSON-encoded.
- **Durable pull consumers**, one per consumer service (`notifications`,
  `analytics`). Distinct durable names = independent cursors, so each service
  receives every event (fan-out) and resumes after downtime (durability).
- Shared client code lives in **`@vortex/events`** (3+ services need it, ADR-008),
  keeping `nats` an implementation detail behind `connect/publish/consume`
  helpers.
- Publishing is **fire-and-forget for the request flow**: a publish failure is
  logged, never fails the HTTP response — async must not couple back into sync.

Verified on Bun via a throwaway spike (connect → stream → publish → durable
consume + ack) before adoption.

## Consequences

**Positive**

- True decoupling: add a reactor (e.g. a future fraud check) by adding a durable
  consumer — zero producer changes.
- Durable + at-least-once: consumers catch up after restarts (JetStream tracks
  acks); demonstrated by independent `notifications`/`analytics` cursors.
- Lightweight single binary; trivial in compose and K8s; monitoring endpoint for
  health.
- One mental model for "this happened" vs REST's "answer me now" (ADR-003).

**Negative / risks**

- At-least-once means consumers must tolerate **duplicate** deliveries
  (idempotency). Trivial here; noted for real handlers.
- JetStream adds stream/consumer config and storage to reason about vs plain
  pub/sub.
- Another stateful component to run.
  - **Mitigation:** acceptable; it's core to the async story and a deliberate
    learning target.

## Alternatives considered

- **NATS core (no JetStream)** — simplest pub/sub, but no durability: a consumer
  that's down loses events. Rejected — durability is required.
- **Kafka / Redpanda** — the heavyweight standard for event streaming, but heavy
  to run and operate for trivial demo volume; overkill against the "lightweight,
  cloud-native" priority. Rejected for v1 (a strong choice if scale were real).
- **RabbitMQ** — solid broker, but heavier and a different (AMQP) model; NATS is
  lighter and pairs better with the K8s/KEDA story. Rejected.
- **Redis Streams** — possible, but Redis would be a second role (cache + bus)
  and a weaker fit than a purpose-built messaging system. Rejected.
