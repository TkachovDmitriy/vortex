import { Hono } from 'hono'
import { eq } from 'drizzle-orm'
import type { CreateOrderRequest, OrderResponse } from '@vortex/shared-types'
import { db } from '../db/client.ts'
import { orders as ordersTable, type OrderRow } from '../db/schema.ts'
import { incr } from '../lib/metrics.ts'

/**
 * The orders REST API. orders is the only writer of its own database (ADR-007).
 * The gateway forwards client calls here; later orders will also call inventory
 * (the sync path) and emit `order.created` to NATS (ADR-006).
 */
export const orders = new Hono()

function toResponse(row: OrderRow): OrderResponse {
  return {
    orderId: row.id,
    item: row.item,
    quantity: row.quantity,
    status: row.status as OrderResponse['status'],
  }
}

orders.post('/orders', async (c) => {
  const body = (await c.req.json()) as CreateOrderRequest
  if (!body.item || typeof body.quantity !== 'number' || body.quantity <= 0) {
    return c.json({ error: 'invalid_order' }, 400)
  }

  const [row] = await db
    .insert(ordersTable)
    .values({ item: body.item, quantity: body.quantity, status: 'created' })
    .returning()

  // count successful creations only (after the insert, not on every attempt).
  incr('orders_created_total')

  // TODO(ADR-006): emit `order.created` to NATS here once the event backbone lands.
  return c.json(toResponse(row!), 201)
})

orders.get('/orders/:id', async (c) => {
  const id = c.req.param('id')
  const [row] = await db.select().from(ordersTable).where(eq(ordersTable.id, id))
  if (!row) return c.json({ error: 'not_found' }, 404)
  return c.json(toResponse(row))
})
