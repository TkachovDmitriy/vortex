import { createApp } from './app.ts'
import { config } from './config.ts'
import { startConsumer } from './consumer.ts'

// Consume in the background; the HTTP server only serves health/metrics.
startConsumer().catch((err) => console.error('notifications: consumer failed:', err))

const app = createApp()
const server = Bun.serve({ port: config.port, fetch: app.fetch })
console.log(`notifications listening on http://localhost:${server.port}`)
