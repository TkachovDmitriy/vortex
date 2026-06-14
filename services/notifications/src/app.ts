import { Hono } from 'hono'
import { health } from './routes/health.ts'

/** Builds the notifications Hono app — operational endpoints only. */
export function createApp(): Hono {
  const app = new Hono()
  app.route('/', health)
  app.notFound((c) => c.json({ error: 'not_found' }, 404))
  return app
}
