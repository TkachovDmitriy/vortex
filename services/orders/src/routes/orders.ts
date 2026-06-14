import { Hono } from 'hono'
import { eq } from 'drizzle-orm'
import type { CreateOrderRequest, OrderResponse } from '@vortex/shared-types'
import { db } from '../db/client.ts'
import { orders as ordersTable, type OrderRow } from '../db/schema.ts'
import { incr } from '../lib/metrics.ts'
import { checkStock, InventoryUnavailableError } from '../lib/inventory.ts'
import { emitOrderCreated } from '../lib/events.ts'

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

  // The synchronous path (ADR-003): ask inventory whether there's enough stock
  // before confirming. If inventory is unreachable, we cannot decide — surface
  // 503 (the cost of sync coupling).
  let status: OrderResponse['status']
  try {
    const stock = await checkStock(body.item)
    status = stock.available >= body.quantity ? 'created' : 'rejected'
  } catch (err) {
    if (err instanceof InventoryUnavailableError) {
      return c.json({ error: 'inventory_unavailable' }, 503)
    }
    throw err
  }

  const [row] = await db
    .insert(ordersTable)
    .values({ item: body.item, quantity: body.quantity, status })
    .returning()

  incr('orders_created_total')
  if (status === 'rejected') incr('orders_rejected_total')

  // The async path (ADR-006): announce the order; notifications + analytics
  // react whenever. Fire-and-forget — a publish failure never fails the request.
  await emitOrderCreated({
    orderId: row!.id,
    item: row!.item,
    quantity: row!.quantity,
    status: row!.status as OrderResponse['status'],
    createdAt: row!.createdAt.toISOString(),
  })

  return c.json(toResponse(row!), 201)
})

orders.get('/orders/:id', async (c) => {
  const id = c.req.param('id')
  const [row] = await db.select().from(ordersTable).where(eq(ordersTable.id, id))
  if (!row) return c.json({ error: 'not_found' }, 404)
  return c.json(toResponse(row))
})
