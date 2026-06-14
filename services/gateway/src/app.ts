import { Hono } from 'hono'
import { logger } from 'hono/logger'
import { health } from './routes/health.ts'
import { orders } from './routes/orders.ts'

/** Builds the gateway's Hono application (routes + middleware). */
export function createApp(): Hono {
  const app = new Hono()

  app.use('*', logger())

  app.route('/', health)
  app.route('/', orders)

  app.notFound((c) => c.json({ error: 'not_found' }, 404))
  app.onError((err, c) => {
    console.error('gateway error:', err)
    return c.json({ error: 'internal_error' }, 502)
  })

  return app
}
