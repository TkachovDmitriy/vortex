import { connectNats, consumeOrderCreated } from '@vortex/events'
import type { OrderCreatedEvent } from '@vortex/shared-types'
import { config } from './config.ts'
import { incr } from './lib/metrics.ts'

/**
 * Independent durable consumer ("analytics") on the same stream as notifications
 * — both receive every order.created (JetStream fan-out). Demonstrates adding a
 * reaction without touching the producer.
 */
export async function startConsumer(): Promise<void> {
  let nc
  for (let attempt = 1; ; attempt++) {
    try {
      nc = await connectNats(config.natsUrl)
      break
    } catch (err) {
      if (attempt >= 10) throw err
      console.warn(`analytics: NATS connect failed (attempt ${attempt}), retrying...`)
      await Bun.sleep(1000)
    }
  }

  console.log('analytics: connected to NATS, consuming order.created')
  await consumeOrderCreated(nc, 'analytics', (event: OrderCreatedEvent) => {
    incr('analytics_orders_total')
    if (event.status === 'rejected') incr('analytics_orders_rejected_total')
    console.log(
      `analytics: 📊 recorded order ${event.orderId} (${event.item} x${event.quantity}) → ${event.status}`,
    )
  })
}
