import { connectNats, consumeOrderCreated } from '@vortex/events'
import type { OrderCreatedEvent } from '@vortex/shared-types'
import { config } from './config.ts'
import { incr } from './lib/metrics.ts'

/** Connect (with startup retry) and consume order.created forever. */
export async function startConsumer(): Promise<void> {
  let nc
  for (let attempt = 1; ; attempt++) {
    try {
      nc = await connectNats(config.natsUrl)
      break
    } catch (err) {
      if (attempt >= 10) throw err
      console.warn(`notifications: NATS connect failed (attempt ${attempt}), retrying...`)
      await Bun.sleep(1000)
    }
  }

  console.log('notifications: connected to NATS, consuming order.created')
  await consumeOrderCreated(nc, 'notifications', (event: OrderCreatedEvent) => {
    incr('notifications_sent_total')
    console.log(
      `notifications: 📧 order ${event.orderId} (${event.item} x${event.quantity}) → ${event.status}`,
    )
  })
}
