# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# DSB Lite production image — Chainguard images only.
#
# Build stage uses the `-dev` variant (includes npm + a shell); the runtime
# stage uses the minimal, distroless Chainguard Node image which runs as a
# non-root user by default and has `node` as its entrypoint.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Stage 1: install production dependencies only.
# ---------------------------------------------------------------------------
FROM cgr.dev/chainguard/node:latest-dev AS deps

WORKDIR /app

# The -dev image already runs as the non-root `node` user; ensure it owns /app.
USER root
RUN chown -R node:node /app
USER node

# Copy manifests first to maximize Docker layer caching.
COPY --chown=node:node package.json package-lock.json* ./

# Install only production dependencies. Use `npm ci` when a lockfile exists for
# reproducible builds; fall back to `npm install` otherwise.
RUN if [ -f package-lock.json ]; then \
      npm ci --omit=dev; \
    else \
      npm install --omit=dev; \
    fi && \
    npm cache clean --force

# ---------------------------------------------------------------------------
# Stage 2: runtime image (minimal, distroless, non-root by default).
# ---------------------------------------------------------------------------
FROM cgr.dev/chainguard/node:latest AS runtime

# Build-time metadata surfaced by /api/version. Overridden by the CI pipeline.
ARG APP_VERSION=1.0.0
ARG BUILD_TIME=unknown
ARG GIT_COMMIT=unknown

ENV NODE_ENV=production \
    APP_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0 \
    APP_VERSION=${APP_VERSION} \
    BUILD_TIME=${BUILD_TIME} \
    GIT_COMMIT=${GIT_COMMIT}

WORKDIR /app

# Bring in installed node_modules from the deps stage.
COPY --from=deps --chown=node:node /app/node_modules ./node_modules

# Copy application source and static assets.
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src
COPY --chown=node:node public ./public

EXPOSE 3000

# Container-level health check (complements the ALB target-group check).
# The Chainguard runtime image is distroless (no shell), so use node's exec form.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://127.0.0.1:'+(process.env.PORT||3000)+'/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"]

# The Chainguard Node image's entrypoint is already `node` and it runs as the
# non-root `node` user, so CMD only needs to supply the script path.
CMD ["src/server.js"]
