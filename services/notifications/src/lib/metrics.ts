/**
 * Minimal Prometheus-format metrics (hand-rolled — golden rule #6). Duplicated
 * per service for now; a shared @vortex service-kit is the natural promotion
 * once it earns it (ADR-008).
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
