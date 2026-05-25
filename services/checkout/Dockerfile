# Checkout Service — Hardened Dockerfile
# P2 Fix: CVE-2026-31789 OpenSSL CRITICAL
# P3 Fix: CVE-2026-42033 axios HIGH (checkout calls axios on every POST /checkout)

FROM node:20-alpine

RUN apk upgrade --no-cache libcrypto3 libssl3
RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1000
WORKDIR /app
COPY package*.json ./
RUN npm install --production
RUN npm install axios@1.15.2 --save
COPY server.js .
USER appuser
EXPOSE 3001
HEALTHCHECK --interval=15s --timeout=3s \
  CMD wget -qO- http://localhost:3001/health || exit 1
CMD ["node", "server.js"]
