/** Runtime configuration, sourced from the environment. */
export interface AnalyticsConfig {
  readonly port: number
  readonly natsUrl: string
}

export const config: AnalyticsConfig = {
  port: Number(process.env.PORT ?? 3004),
  natsUrl: process.env.NATS_URL ?? 'nats://localhost:4222',
}
