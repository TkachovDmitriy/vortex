/**
 * Minimal Prometheus-format metrics.
 *
 * Hand-rolled on purpose: golden rule #6 says verify a dependency on Bun before
 * adopting it. A real client (`prom-client`) is the Phase 3 (observability)
 * decision — until then this exposes just enough for a /metrics scrape target.
 */

const counters = new Map<string, number>()

export function incr(name: string): void {
  counters.set(name, (counters.get(name) ?? 0) + 1)
}

export function renderMetrics(): string {
  const lines: string[] = []
  for (const [name, value] of counters) {
    lines.push(`# TYPE ${name} counter`)
    lines.push(`${name} ${value}`)
  }
  return lines.join('\n') + '\n'
}
