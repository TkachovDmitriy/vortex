import { pgTable, uuid, text, integer, timestamp } from 'drizzle-orm/pg-core'

/**
 * The orders table — deliberately trivial (golden rule #3). The point is the
 * database-per-service boundary (ADR-007), not a rich domain model.
 */
export const orders = pgTable('orders', {
  id: uuid('id').primaryKey().defaultRandom(),
  item: text('item').notNull(),
  quantity: integer('quantity').notNull(),
  status: text('status').notNull().default('created'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
})

export type OrderRow = typeof orders.$inferSelect
export type NewOrderRow = typeof orders.$inferInsert
