# syntax=docker/dockerfile:1
# Multi-stage build for @vortex/orders (ADR-004).
# Build context is the repo root so Bun can resolve the workspace.

# ---- install: resolve workspace dependencies ----
FROM oven/bun:1.3-slim AS install
WORKDIR /app
COPY package.json bun.lock ./
COPY packages/tsconfig/package.json ./packages/tsconfig/
COPY packages/shared-types/package.json ./packages/shared-types/
COPY services/orders/package.json ./services/orders/
RUN bun install --frozen-lockfile

# ---- release: copy deps + source, run as non-root ----
FROM oven/bun:1.3-slim AS release
WORKDIR /app
ENV NODE_ENV=production
COPY --from=install /app/node_modules ./node_modules
COPY packages ./packages
COPY services/orders ./services/orders
USER bun
EXPOSE 3000
WORKDIR /app/services/orders
CMD ["bun", "src/index.ts"]
