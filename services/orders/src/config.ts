/** Runtime configuration, sourced from the environment. */
export interface OrdersConfig {
  readonly port: number
  readonly databaseUrl: string
  readonly inventoryUrl: string
  readonly natsUrl: string
}

export const config: OrdersConfig = {
  port: Number(process.env.PORT ?? 3001),
  // orders owns its own database (ADR-007). In compose/K8s this resolves via
  // service DNS; locally it defaults to a dev Postgres.
  databaseUrl:
    process.env.DATABASE_URL ?? 'postgres://vortex:vortex@localhost:5432/orders',
  // The synchronous "need an answer now" dependency (ADR-003): orders queries
  // inventory for stock before confirming. Resolves via service DNS in compose/K8s.
  inventoryUrl: process.env.INVENTORY_URL ?? 'http://localhost:3002',
  // The async backbone (ADR-006): orders publishes order.created here.
  natsUrl: process.env.NATS_URL ?? 'nats://localhost:4222',
}
