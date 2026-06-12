import { drizzle } from 'drizzle-orm/bun-sql'
import { config } from '../config.ts'
import * as schema from './schema.ts'

/**
 * Drizzle over Bun's native SQL driver (`drizzle-orm/bun-sql`, ADR-007) — no
 * separate pg client. This is also the golden-rule-#6 Bun-compatibility check
 * for the data layer (ADR-009).
 */
export const db = drizzle(config.databaseUrl, { schema })
