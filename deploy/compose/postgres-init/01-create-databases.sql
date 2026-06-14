-- Database-per-service (ADR-007). In Phase 1 the per-service databases are
-- separate logical databases inside one Postgres container (cheap locally);
-- the boundary is enforced in the architecture, not by separate servers.
CREATE DATABASE orders;
CREATE DATABASE inventory;
