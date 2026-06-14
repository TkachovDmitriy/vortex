/** Runtime configuration, sourced from the environment. */
export interface GatewayConfig {
  readonly port: number
  readonly ordersUrl: string
}

export const config: GatewayConfig = {
  port: Number(process.env.PORT ?? 3000),
  // Internal address of the orders service. In compose/K8s this resolves via
  // service DNS (e.g. http://orders:3000); locally it defaults to a dev port.
  ordersUrl: process.env.ORDERS_URL ?? 'http://localhost:3001',
}
