'use strict';

const path = require('path');
const express = require('express');

const app = express();

// ---------------------------------------------------------------------------
// Configuration (all sourced from environment variables with safe defaults so
// the app runs locally without any setup).
// ---------------------------------------------------------------------------
const PORT = parseInt(process.env.PORT || '3000', 10);
const HOST = process.env.HOST || '0.0.0.0';

// Metadata surfaced through /api/version. These are injected at build time via
// Docker build args / ECS task-definition environment variables.
const APP_VERSION = process.env.APP_VERSION || require('../package.json').version;
const APP_ENV = process.env.APP_ENV || process.env.NODE_ENV || 'development';
const BUILD_TIME = process.env.BUILD_TIME || 'unknown';
const GIT_COMMIT = process.env.GIT_COMMIT || 'unknown';

// The process start time lets us report uptime on the health check.
const STARTED_AT = new Date();

// Trust the ALB proxy so req.ip / X-Forwarded-* headers are handled correctly.
app.set('trust proxy', true);

// Disable the framework fingerprint header.
app.disable('x-powered-by');

// ---------------------------------------------------------------------------
// API routes (declared before static middleware so they always take priority).
// ---------------------------------------------------------------------------

// Health check used by the ALB target group. Kept intentionally cheap and
// dependency-free so it responds fast and never fails on downstream services.
app.get('/health', (_req, res) => {
  res.status(200).json({
    status: 'ok',
    uptimeSeconds: Math.floor((Date.now() - STARTED_AT.getTime()) / 1000),
    timestamp: new Date().toISOString(),
  });
});

// Version / build metadata. Useful for verifying which image is actually
// running behind the load balancer after a deployment.
app.get('/api/version', (_req, res) => {
  res.status(200).json({
    name: 'DSB Lite',
    version: APP_VERSION,
    environment: APP_ENV,
    buildTime: BUILD_TIME,
    gitCommit: GIT_COMMIT,
  });
});

// ---------------------------------------------------------------------------
// Static single-page website.
// ---------------------------------------------------------------------------
const publicDir = path.join(__dirname, '..', 'public');
// Caching is disabled for all static assets so the latest deploy is always
// served (no stale CSS/JS/images behind the load balancer or in browsers).
const noCacheHeaders = (res) => {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
};

app.use(
  express.static(publicDir, {
    extensions: ['html'],
    etag: false,
    lastModified: false,
    cacheControl: false,
    maxAge: 0,
    setHeaders: (res) => noCacheHeaders(res),
  })
);

// SPA-style fallback: any unmatched, non-API GET returns the landing page.
app.get('*', (req, res, next) => {
  if (req.path.startsWith('/api') || req.path === '/health') {
    return next();
  }
  noCacheHeaders(res);
  res.sendFile(path.join(publicDir, 'index.html'), {
    etag: false,
    lastModified: false,
    cacheControl: false,
  });
});

// 404 handler for anything that slipped through (e.g. unknown API paths).
app.use((req, res) => {
  res.status(404).json({ error: 'Not Found', path: req.path });
});

// Centralized error handler.
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal Server Error' });
});

// ---------------------------------------------------------------------------
// Server bootstrap + graceful shutdown.
// ---------------------------------------------------------------------------
const server = app.listen(PORT, HOST, () => {
  console.log(
    `DSB Lite listening on http://${HOST}:${PORT} ` +
      `(env=${APP_ENV}, version=${APP_VERSION}, commit=${GIT_COMMIT})`
  );
});

function shutdown(signal) {
  console.log(`Received ${signal}, shutting down gracefully...`);
  server.close(() => {
    console.log('HTTP server closed.');
    process.exit(0);
  });
  // Force-exit if connections do not drain in time.
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = app;
