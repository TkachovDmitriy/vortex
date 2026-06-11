import { createApp } from './app.ts'
import { config } from './config.ts'

const app = createApp()

const server = Bun.serve({
  port: config.port,
  fetch: app.fetch,
})

console.log(`gateway listening on http://localhost:${server.port}`)
