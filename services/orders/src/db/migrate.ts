import { migrate } from 'drizzle-orm/bun-sql/migrator'
import { db } from './client.ts'

/** Applies pending migrations from ./migrations, then exits. */
await migrate(db, { migrationsFolder: `${import.meta.dir}/../../migrations` })
console.log('orders: migrations applied')
process.exit(0)
