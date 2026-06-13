import { sql } from 'drizzle-orm'
import { db } from './client.ts'
import { stock } from './schema.ts'

/** Idempotent seed of demo stock levels. */
const items: (typeof stock.$inferInsert)[] = [
  { item: 'widget', available: 100 },
  { item: 'gizmo', available: 5 },
  { item: 'gadget', available: 0 },
]

for (let attempt = 1; ; attempt++) {
  try {
    await db
      .insert(stock)
      .values(items)
      .onConflictDoUpdate({ target: stock.item, set: { available: sql`excluded.available` } })
    console.log(`inventory: seeded ${items.length} stock items`)
    process.exit(0)
  } catch (err) {
    if (attempt >= 10) {
      console.error('inventory: seed failed after retries:', err)
      process.exit(1)
    }
    console.warn(`inventory: seed attempt ${attempt} failed, retrying...`)
    await Bun.sleep(1000)
  }
}
