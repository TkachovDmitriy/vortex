/**
 * Shared REST contracts between vortex services.
 *
 * These are the v1 mitigation for "REST is untyped on the wire" (ADR-003):
 * both ends of a synchronous call import the same shape from here, so the
 * gateway, orders, and inventory agree on request/response structure without
 * a codegen pipeline. When gRPC/ConnectRPC lands (ADR-005), generated types
 * supersede these.
 */

/** Client → gateway → orders: place an order. */
export interface CreateOrderRequest {
  item: string
  quantity: number
}

export type OrderStatus = 'created' | 'rejected'

/** orders → gateway → client: the result of placing an order. */
export interface OrderResponse {
  orderId: string
  item: string
  quantity: number
  status: OrderStatus
}

/** orders → inventory (the synchronous "need an answer now" path). */
export interface StockCheckResponse {
  item: string
  available: number
  inStock: boolean
}
