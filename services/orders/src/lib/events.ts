import {
  connectNats,
  ensureOrderStream,
  publishOrderCreated,
  type NatsConnection,
} from '@vortex/events'
import type { OrderCreatedEvent } from '@vortex/shared-types'
import { config } from '../config.ts'

let nc: NatsConnection | undefined

/**
 * Connect to NATS and ensure the ORDERS stream exists (orders owns it).
 * Non-fatal: if NATS is down, orders still serves the synchronous path; events
 * are simply skipped (async is "react whenever", not "block the request").
 */
export async function initEvents(): Promise<void> {
  try {
    nc = await connectNats(config.natsUrl)
    await ensureOrderStream(nc)
    console.log('orders: connected to NATS, ORDERS stream ready')
  } catch (err) {
    console.error('orders: NATS unavailable, events disabled:', err)
  }
}

/** Publish order.created — failures are logged, never fail the HTTP request. */
export async function emitOrderCreated(event: OrderCreatedEvent): Promise<void> {
  if (!nc) return
  try {
    await publishOrderCreated(nc, event)
  } catch (err) {
    console.error('orders: failed to publish order.created:', err)
  }
}
