/** Runtime configuration, sourced from the environment. */
export interface NotificationsConfig {
  readonly port: number
  readonly natsUrl: string
}

export const config: NotificationsConfig = {
  port: Number(process.env.PORT ?? 3003),
  natsUrl: process.env.NATS_URL ?? 'nats://localhost:4222',
}
