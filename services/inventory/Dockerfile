# syntax=docker/dockerfile:1
# Multi-stage build for @vortex/inventory (ADR-004).
# Build context is the repo root so Bun can resolve the workspace.

# ---- install: resolve workspace dependencies ----
FROM oven/bun:1.3-slim AS install
WORKDIR /app
# All workspace manifests first: --frozen-lockfile must see the whole workspace.
COPY package.json bun.lock ./
COPY packages/tsconfig/package.json ./packages/tsconfig/
COPY packages/shared-types/package.json ./packages/shared-types/
COPY packages/events/package.json ./packages/events/
COPY services/gateway/package.json ./services/gateway/
COPY services/orders/package.json ./services/orders/
COPY services/inventory/package.json ./services/inventory/
COPY services/notifications/package.json ./services/notifications/
COPY services/analytics/package.json ./services/analytics/
RUN bun install --frozen-lockfile --production

# ---- release: copy deps + source, run as non-root ----
FROM oven/bun:1.3-slim AS release
WORKDIR /app
ENV NODE_ENV=production
COPY packages ./packages
COPY services/inventory ./services/inventory
# Bun's isolated linker keeps deps per workspace — copy both the root store and
# this service's node_modules (after source; the context excludes node_modules).
COPY --from=install /app/node_modules ./node_modules
COPY --from=install /app/services/inventory/node_modules ./services/inventory/node_modules
# Patch base-image OS packages against known CVEs (Trivy gates on HIGH/CRITICAL).
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*
USER bun
EXPOSE 3000
WORKDIR /app/services/inventory
CMD ["bun", "src/index.ts"]
