import { Hono } from 'hono'
import { renderMetrics } from '../lib/metrics.ts'

/**
 * Even though notifications has no business HTTP API (it's a NATS consumer), it
 * still serves /health and /metrics for K8s probes and Prometheus scraping.
 */
export const health = new Hono()

health.get('/health', (c) => c.json({ status: 'ok' }))

health.get('/metrics', (c) =>
  c.text(renderMetrics(), 200, { 'content-type': 'text/plain; version=0.0.4' }),
)
