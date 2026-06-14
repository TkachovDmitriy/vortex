import { Hono } from 'hono'
import { renderMetrics } from '../lib/metrics.ts'

/** Operational endpoints: liveness/readiness (K8s probes) and metrics scrape. */
export const health = new Hono()

health.get('/health', (c) => c.json({ status: 'ok' }))

health.get('/metrics', (c) =>
  c.text(renderMetrics(), 200, { 'content-type': 'text/plain; version=0.0.4' }),
)
