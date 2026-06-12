/** Runtime configuration, sourced from the environment. */
export interface OrdersConfig {
  readonly port: number
  readonly databaseUrl: string
}

export const config: OrdersConfig = {
  port: Number(process.env.PORT ?? 3001),
  // orders owns its own database (ADR-007). In compose/K8s this resolves via
  // service DNS; locally it defaults to a dev Postgres.
  databaseUrl:
    process.env.DATABASE_URL ?? 'postgres://vortex:vortex@localhost:5432/orders',
}
