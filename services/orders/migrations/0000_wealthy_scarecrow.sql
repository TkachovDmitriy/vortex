CREATE TABLE "orders" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"item" text NOT NULL,
	"quantity" integer NOT NULL,
	"status" text DEFAULT 'created' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
