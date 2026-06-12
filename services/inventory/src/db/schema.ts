import { pgTable, text, integer } from 'drizzle-orm/pg-core'

/**
 * Stock levels per item — trivial by design (golden rule #3). inventory owns
 * this table exclusively (ADR-007); other services read stock only over REST.
 */
export const stock = pgTable('stock', {
  item: text('item').primaryKey(),
  available: integer('available').notNull().default(0),
})

export type StockRow = typeof stock.$inferSelect
