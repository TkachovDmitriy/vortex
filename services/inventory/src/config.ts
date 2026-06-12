/** Runtime configuration, sourced from the environment. */
export interface InventoryConfig {
  readonly port: number
  readonly databaseUrl: string
}

export const config: InventoryConfig = {
  port: Number(process.env.PORT ?? 3002),
  // inventory owns its own database (ADR-007), separate from orders'.
  databaseUrl:
    process.env.DATABASE_URL ?? 'postgres://vortex:vortex@localhost:5432/inventory',
}
