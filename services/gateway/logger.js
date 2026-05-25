'use strict';
// Structured JSON Logger — used by all 4 services
// Enables X-Request-Id correlation across service boundaries
// Log format: { timestamp, level, service, requestId, method, path, status, durationMs }
// Evidence: Figure JSON-1 through JSON-4 in CA2 report

const SERVICE_NAME = process.env.SERVICE_NAME || 'unknown';

function log(level, message, fields = {}) {
  process.stdout.write(JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    service: SERVICE_NAME,
    message,
    ...fields,
  }) + '\n');
}

function logRequest(requestId, method, path, extra = {}) {
  log('info', `${method} ${path} received`, { requestId, method, path, ...extra });
}

function logResponse(requestId, status, durationMs, extra = {}) {
  log('info', `${status} response`, { requestId, status, durationMs, ...extra });
}

function logError(requestId, message, extra = {}) {
  log('error', message, { requestId, ...extra });
}

module.exports = { log, logRequest, logResponse, logError };
