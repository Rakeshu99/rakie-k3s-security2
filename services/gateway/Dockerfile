# Gateway Service — Hardened Dockerfile
# P2 Fix: RUN apk upgrade libcrypto3 libssl3 — fixes CVE-2026-31789 (OpenSSL CRITICAL CVSS 9.8)
# P3 Fix: RUN npm install axios@1.15.2 — fixes CVE-2026-42033 (axios HIGH CVSS 8.1)
#
# Commands used to build and deploy:
#   docker build -t rakie-gateway:hardened ./gateway/
#   docker save rakie-gateway:hardened | sudo k3s ctr images import -
#   kubectl set image deployment/gateway gateway=rakie-gateway:hardened -n rakie
#   kubectl rollout restart deployment/gateway -n rakie
#
# Post-fix Trivy result: CRITICAL: 0 (alpine 3.23.4: 0 vulnerabilities)

FROM node:20-alpine

# P2: Fix CVE-2026-31789 (OpenSSL heap overflow, CVSS 9.8)
# Upgrades libcrypto3 from 3.5.5-r0 (vulnerable) to 3.5.6-r0 (fixed)
RUN apk upgrade --no-cache libcrypto3 libssl3

RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1000
WORKDIR /app
COPY package*.json ./
RUN npm install --production

# P3: Fix CVE-2026-42033 (axios prototype pollution, CVSS 8.1)
# Upgrades axios from 1.14.0 (vulnerable) to 1.15.2 (fixed)
RUN npm install axios@1.15.2 --save

COPY server.js .
USER appuser
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=3s \
  CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "server.js"]
