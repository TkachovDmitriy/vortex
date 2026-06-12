import { drizzle } from 'drizzle-orm/bun-sql'
import { config } from '../config.ts'
import * as schema from './schema.ts'

/** Drizzle over Bun's native SQL driver (`drizzle-orm/bun-sql`, ADR-007). */
export const db = drizzle(config.databaseUrl, { schema })
