import { Hono } from 'hono'
import { eq } from 'drizzle-orm'
import type { StockCheckResponse } from '@vortex/shared-types'
import { db } from '../db/client.ts'
import { stock } from '../db/schema.ts'
import { incr } from '../lib/metrics.ts'

/**
 * The inventory read API — the synchronous "need an answer now" path (ADR-003).
 * orders calls this before confirming an order. Unknown items report zero stock
 * rather than 404, so the caller always gets a usable answer.
 */
export const stockRoutes = new Hono()

stockRoutes.get('/stock/:item', async (c) => {
  incr('inventory_stock_queries_total')

  const item = c.req.param('item')
  const [row] = await db.select().from(stock).where(eq(stock.item, item))
  const available = row?.available ?? 0

  const res: StockCheckResponse = { item, available, inStock: available > 0 }
  return c.json(res)
})
