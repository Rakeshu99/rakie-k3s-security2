# Security Findings — P1 through P8

> EAD CA2 · Rakesh Uday Kumar (A00047386) · TU Dublin · May 2026  
> Platform: K3s v1.34.6, namespace: rakie  
> All findings identified via Trivy v0.70.0, kubeaudit v0.22.2, and runtime penetration tests

---

## P1 — No NetworkPolicy (CVSS 9.8 CRITICAL)

**Finding:** No NetworkPolicy configured in the rakie namespace. Any pod can reach any other pod without restriction — including the postgres database.

**Evidence:** `kubectl get networkpolicies -n rakie` returned empty before fix.

**Impact:** A compromised container anywhere in the namespace has direct TCP access to postgres:5432. Combined with P2/P3 CVEs, this creates a complete exploit chain: CVE-2026-42033 code execution → read `DB_PASSWORD` env var → connect directly to postgres.

**Fix applied:**
```bash
kubectl apply -f k8s/networkpolicy/00-default-deny-all.yaml
kubectl apply -f k8s/networkpolicy/01-allow-rules.yaml
```

**Verified:** CT-6 and CT-7 — inventory and pricing both return `nc: bad address` after NetworkPolicy applied.

**Status: APPLIED** ✅

---

## P2 — CVE-2026-31789 OpenSSL Heap Overflow (CVSS 9.8 CRITICAL)

**Finding:** All 4 application images use node:20-alpine with libcrypto3 version 3.5.5-r0, which contains a heap overflow in OpenSSL's PKCS#12 parsing.

**CVE details:**
- CVE: CVE-2026-31789
- CVSS: 9.8 (Critical)
- Component: libcrypto3 3.5.5-r0
- Fixed in: 3.5.6-r0
- Exploitable: Remotely, no authentication required

**Fix applied:**
```dockerfile
RUN apk upgrade --no-cache libcrypto3 libssl3
```
Added to all 4 Dockerfiles immediately after the FROM line.

**Verified:** Post-fix Trivy scan on all 4 :hardened images — `CRITICAL: 0`. Alpine OS layer shows 0 vulnerabilities.

**Status: APPLIED** ✅

---

## P3 — CVE-2026-42033 axios Prototype Pollution (CVSS 8.1 HIGH)

**Finding:** gateway and checkout use axios 1.14.0, which is vulnerable to prototype pollution via crafted request headers.

**CVE details:**
- CVE: CVE-2026-42033
- CVSS: 8.1 (High)
- Component: axios 1.14.0
- Fixed in: 1.15.2
- Exploitable: On every POST /api/checkout request

**Fix applied:**
```dockerfile
RUN npm install axios@1.15.2 --save
```
Added to gateway and checkout Dockerfiles only. pricing and inventory make no outbound HTTP calls and do not use axios.

**Verified:** Post-fix Trivy scan — `app/node_modules/axios/package.json: 0 vulnerabilities`.

**Status: APPLIED** ✅

---

## P4 — allowPrivilegeEscalation:true (CVSS 7.8 HIGH)

**Finding:** No securityContext configured on any deployment. Containers run with default privileges — allowPrivilegeEscalation defaults to true, enabling setuid escalation inside the container.

**Fix applied:**
```bash
kubectl patch deployment gateway checkout pricing inventory \
  -n rakie --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/securityContext/allowPrivilegeEscalation","value":false}]'
```

**Verified:** FX-3 — gateway deployment YAML confirms `allowPrivilegeEscalation: false` and `capabilities.drop: [ALL]`.

**Status: APPLIED** ✅

---

## P5 — readOnlyRootFilesystem:false + SA Token Automounted (CVSS 5.5/7.5)

**Finding (readOnlyFS):** Writable root filesystem allows an attacker who gains code execution to write binaries that persist across the pod lifetime.

**Finding (SA token):** Default SA token automounted on every pod. Confirmed live: `wget kubernetes.default.svc` returns 401 — the API is reachable from inside containers.

**Fix applied (securityContext):**
```yaml
readOnlyRootFilesystem: true
capabilities:
  drop: [ALL]
```

**Fix applied (SA token):**
```bash
for svc in gateway checkout pricing inventory; do
  kubectl patch deployment $svc -n rakie \
    --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/automountServiceAccountToken","value":false}]'
done
```

**Verified:** SA-3 — all 4 deployments show `automountServiceAccountToken=false`.

**Status: APPLIED** ✅

---

## P6 — Plaintext Credentials in secret.yaml (CVSS 7.5 HIGH)

**Finding:** POSTGRES_PASSWORD stored in plaintext in the `stringData` field of secret.yaml. Visible via `kubectl get secret -o yaml` and in git history.

**Fix applied:**
```bash
kubectl delete secret postgres-secret -n rakie
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=rakie \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 16)" \
  --from-literal=POSTGRES_DB=rakie \
  -n rakie
```

Recreated imperatively — values stored as base64-encoded `data` field, not `stringData`.

**Verified:** SEC-1 — `kubectl describe secret` shows `POSTGRES_PASSWORD: 17 bytes`. No plaintext visible.

**Note:** base64 is encoding, not encryption. Production fix: Bitnami Sealed Secrets.

**Status: APPLIED** ✅

---

## P7 — HTTP-Only Traefik Ingress (CVSS 5.9 MEDIUM)

**Finding:** Traefik ingress configured with `entrypoint: web` (HTTP only). No TLS block, no certificate. All checkout traffic — including order data — transmitted unencrypted.

**Recommended fix:** cert-manager + TLS on Traefik ingress.

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# Create ClusterIssuer and update IngressRoute
# See: https://cert-manager.io/docs/
```

**Reason not applied:** Requires cert-manager infrastructure and IngressRoute reconfiguration. Risk of breaking ingress close to submission. Documented accepted risk.

**Status: RECOMMENDED** 📋

---

## Remaining Accepted Issues

**node-tar HIGH CVEs (11 remaining):**
These are build-time npm CLI dependencies (node-tar, cross-spawn) used by npm itself during `npm install`. They are not present in the application runtime. No upstream fix is available. Will resolve automatically when node:20-alpine ships a patched version.

**AppArmorMissing / SeccompMissing (13 kubeaudit errors):**
These require kernel-level profiles configured at the K3s node level. Not configurable via Kubernetes manifests. Accepted for lab environment.

**postgres runAsNonRoot:**
postgres:15-alpine requires UID 999 for data directory ownership. Forcing runAsNonRoot prevents startup. Accepted exception — mitigated by NetworkPolicy restricting postgres access to checkout only.
