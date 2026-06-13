import { createApp } from './app.ts'
import { config } from './config.ts'
import { initEvents } from './lib/events.ts'

await initEvents()

const app = createApp()

const server = Bun.serve({
  port: config.port,
  fetch: app.fetch,
})

console.log(`orders listening on http://localhost:${server.port}`)
