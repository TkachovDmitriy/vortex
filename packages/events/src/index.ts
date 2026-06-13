/**
 * Shared NATS/JetStream helpers (ADR-006) — the async backbone used by the
 * producer (orders) and consumers (notifications, analytics). Promoted to a
 * shared package because 3+ services need it (ADR-008). Verified on Bun via the
 * golden-rule-#6 spike.
 */
import {
  connect,
  JSONCodec,
  AckPolicy,
  type NatsConnection,
} from 'nats'
import type { OrderCreatedEvent } from '@vortex/shared-types'

// Re-export so consumers of this package don't need a direct `nats` dependency.
export type { NatsConnection } from 'nats'

/** JetStream stream capturing all order events. */
export const ORDER_STREAM = 'ORDERS'
/** Subject for "an order was created". */
export const SUBJECT_ORDER_CREATED = 'order.created'

const orderCodec = JSONCodec<OrderCreatedEvent>()

/** Connect to NATS (e.g. "nats://nats:4222"). */
export function connectNats(servers: string): Promise<NatsConnection> {
  return connect({ servers, name: 'vortex' })
}

/** Idempotently ensure the ORDERS stream exists (producer owns this). */
export async function ensureOrderStream(nc: NatsConnection): Promise<void> {
  const jsm = await nc.jetstreamManager()
  try {
    await jsm.streams.info(ORDER_STREAM)
  } catch {
    await jsm.streams.add({ name: ORDER_STREAM, subjects: ['order.>'] })
  }
}

/** Publish an order.created event (fire-and-forget for the caller's flow). */
export async function publishOrderCreated(
  nc: NatsConnection,
  event: OrderCreatedEvent,
): Promise<void> {
  await nc.jetstream().publish(SUBJECT_ORDER_CREATED, orderCodec.encode(event))
}

/**
 * Subscribe a durable consumer to order.created and invoke `handler` per event.
 * Each distinct `durable` name is an independent consumer, so multiple services
 * (notifications, analytics) each receive every event — JetStream fan-out.
 * Runs until the connection closes.
 */
export async function consumeOrderCreated(
  nc: NatsConnection,
  durable: string,
  handler: (event: OrderCreatedEvent) => Promise<void> | void,
): Promise<void> {
  // Ensure the stream exists before subscribing, so consumers don't depend on
  // the producer having started first (ensureOrderStream is idempotent).
  await ensureOrderStream(nc)

  const jsm = await nc.jetstreamManager()
  await jsm.consumers.add(ORDER_STREAM, {
    durable_name: durable,
    ack_policy: AckPolicy.Explicit,
    filter_subject: SUBJECT_ORDER_CREATED,
  })

  const consumer = await nc.jetstream().consumers.get(ORDER_STREAM, durable)
  const messages = await consumer.consume()
  for await (const m of messages) {
    try {
      await handler(orderCodec.decode(m.data))
      m.ack()
    } catch (err) {
      console.error(`consumer ${durable} handler failed:`, err)
      m.nak()
    }
  }
}
