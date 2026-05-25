#!/usr/bin/env bash
# security/trivy/scan-all.sh
# Commands used in CA2 report for image scanning
# Evidence: Figures T1-T5, CVE-5, CVE-6

set -euo pipefail
NAMESPACE="rakie"

echo "=== TRIVY IMAGE SCAN — BEFORE HARDENING ==="
for img in gateway checkout pricing inventory; do
  echo -e "\n--- rakie-$img:latest ---"
  trivy image rakie-$img:latest \
    --severity CRITICAL,HIGH --no-progress 2>/dev/null \
    | grep "^Total:" || echo "No results"
done

echo -e "\n=== TRIVY IMAGE SCAN — AFTER HARDENING ==="
for img in gateway checkout pricing inventory; do
  echo -e "\n--- rakie-$img:hardened ---"
  trivy image rakie-$img:hardened \
    --severity CRITICAL,HIGH --no-progress 2>/dev/null \
    | grep "^Total:" || echo "No results"
done

echo -e "\n=== DETAILED: rakie-gateway:hardened ==="
trivy image rakie-gateway:hardened \
  --severity CRITICAL,HIGH --no-progress 2>/dev/null | head -30
