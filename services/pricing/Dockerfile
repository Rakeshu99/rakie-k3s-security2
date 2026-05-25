# Pricing Service — Hardened Dockerfile
# P2 Fix: CVE-2026-31789 OpenSSL CRITICAL (no axios — pricing makes no outbound HTTP calls)

FROM node:20-alpine

RUN apk upgrade --no-cache libcrypto3 libssl3
RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1000
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY server.js .
USER appuser
EXPOSE 3002
HEALTHCHECK --interval=15s --timeout=3s \
  CMD wget -qO- http://localhost:3002/health || exit 1
CMD ["node", "server.js"]
