import { migrate } from 'drizzle-orm/bun-sql/migrator'
import { db } from './client.ts'

/**
 * Applies pending migrations, with retry. Bun's bun-sql driver occasionally
 * throws "Connection closed" on the first connection to a just-ready Postgres;
 * migrations are idempotent (tracked in __drizzle_migrations), so retry is safe.
 */
const folder = `${import.meta.dir}/../../migrations`

for (let attempt = 1; ; attempt++) {
  try {
    await migrate(db, { migrationsFolder: folder })
    console.log('inventory: migrations applied')
    process.exit(0)
  } catch (err) {
    if (attempt >= 10) {
      console.error('inventory: migration failed after retries:', err)
      process.exit(1)
    }
    console.warn(`inventory: migrate attempt ${attempt} failed, retrying...`)
    await Bun.sleep(1000)
  }
}
