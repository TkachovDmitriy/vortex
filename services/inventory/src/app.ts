import { Hono } from 'hono'
import { logger } from 'hono/logger'
import { health } from './routes/health.ts'
import { stockRoutes } from './routes/stock.ts'

/** Builds the inventory Hono application (routes + middleware). */
export function createApp(): Hono {
  const app = new Hono()

  app.use('*', logger())

  app.route('/', health)
  app.route('/', stockRoutes)

  app.notFound((c) => c.json({ error: 'not_found' }, 404))
  app.onError((err, c) => {
    console.error('inventory error:', err)
    return c.json({ error: 'internal_error' }, 500)
  })

  return app
}
