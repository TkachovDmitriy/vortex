import type { StockCheckResponse } from '@vortex/shared-types'
import { config } from '../config.ts'

/** Raised when the inventory service can't be reached or errors (sync coupling). */
export class InventoryUnavailableError extends Error {
  constructor(cause?: unknown) {
    super('inventory service unavailable')
    this.name = 'InventoryUnavailableError'
    this.cause = cause
  }
}

/**
 * The synchronous stock check (ADR-003). orders blocks on this answer before
 * deciding an order's fate — the defining trait of the "need an answer now"
 * path, and its trade-off: if inventory is down, orders can't proceed.
 */
export async function checkStock(item: string): Promise<StockCheckResponse> {
  let res: Response
  try {
    res = await fetch(`${config.inventoryUrl}/stock/${encodeURIComponent(item)}`)
  } catch (err) {
    throw new InventoryUnavailableError(err)
  }
  if (!res.ok) throw new InventoryUnavailableError(`status ${res.status}`)
  return (await res.json()) as StockCheckResponse
}
