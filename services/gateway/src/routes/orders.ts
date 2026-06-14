import { Hono } from 'hono'
import type { CreateOrderRequest } from '@vortex/shared-types'
import { config } from '../config.ts'
import { incr } from '../lib/metrics.ts'

/**
 * The API-gateway concept: the public order API. The gateway owns no business
 * logic and no database — it forwards to the orders service and relays the
 * response. This is the seam that later grows into a BFF/aggregator (composing
 * orders + inventory) so it earns its place beyond a plain proxy.
 */
export const orders = new Hono()

orders.post('/orders', async (c) => {
  incr('gateway_orders_requests_total')

  const body = (await c.req.json()) as CreateOrderRequest

  const res = await fetch(`${config.ordersUrl}/orders`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })

  const payload = await res.json()
  return c.json(payload, res.status as 200)
})
