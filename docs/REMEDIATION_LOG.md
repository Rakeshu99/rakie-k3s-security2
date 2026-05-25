# Remediation Log — Chronological Fix Record

> EAD CA2 · Rakesh Uday Kumar (A00047386) · May 2026  
> Every fix applied on live VM `eaduser@EADCA1VM` with terminal evidence

---

## Fix 1 — NetworkPolicy (P1) — CVSS 9.8

**When:** CA2 assessment — first fix applied  
**Why first:** Manifest-only change, zero downtime, eliminates highest blast-radius risk immediately

**Commands:**
```bash
kubectl apply -f k8s/networkpolicy/00-default-deny-all.yaml
kubectl apply -f k8s/networkpolicy/01-allow-rules.yaml
kubectl get networkpolicies -n rakie
```

**Evidence:** Figures FX-1, CT-6, CT-7  
**Result:** 6 NetworkPolicy objects created. Lateral movement confirmed blocked.

---

## Fix 2 — SecurityContext (P4/P5) — CVSS 7.8/5.5

**When:** Alongside P1 — same manifest-only, zero downtime  
**Why:** Forms a coherent hardening layer with P1

**Commands:**
```bash
kubectl apply -f k8s/securitycontext/all-deployments.yaml
kubectl get pods -n rakie
```

**Evidence:** Figures FX-2, FX-3, CT-1  
**Result:** allowPrivilegeEscalation:false, drop:ALL, readOnlyFS:true on all 4 app pods.

---

## Fix 3 — Credentials (P6/P7) — CVSS 7.5

**When:** After NetworkPolicy — pod restart required, safe once lateral movement blocked  
**Why P7 in report:** P6 in report is `allowPrivEsc`, P7 is credentials

**Commands:**
```bash
kubectl delete secret postgres-secret -n rakie
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=rakie \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 16)" \
  --from-literal=POSTGRES_DB=rakie \
  -n rakie
kubectl describe secret postgres-secret -n rakie
```

**Evidence:** Figures SEC-1 through SEC-5  
**Result:** base64 data field confirmed. No plaintext visible in describe or manifest.

---

## Fix 4 — SA Token (P5) — CVSS 7.5

**When:** Same session — kubectl patch, zero downtime  
**Why:** Simple manifest change, no rebuild required

**Commands:**
```bash
for svc in gateway checkout pricing inventory; do
  kubectl patch deployment $svc -n rakie \
    --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/automountServiceAccountToken","value":false}]'
done
```

**Evidence:** Figures SA-1 through SA-4  
**Result:** automountServiceAccountToken=false confirmed on all 4 deployments.

---

## Fix 5 — CVE Remediation (P2/P3) — CVSS 9.8/8.1

**When:** After manifest-only fixes — required Dockerfile changes and image rebuild  
**Why last among applied:** Medium effort — rebuild + K3s import

**Commands:**
```bash
# Dockerfile changes
sed -i '/^FROM/a RUN apk upgrade --no-cache libcrypto3 libssl3' \
  gateway/Dockerfile checkout/Dockerfile pricing/Dockerfile inventory/Dockerfile
sed -i '/npm install/a RUN npm install axios@1.15.2 --save' \
  gateway/Dockerfile checkout/Dockerfile

# Rebuild
docker build -t rakie-gateway:hardened   ./gateway/
docker build -t rakie-checkout:hardened  ./checkout/
docker build -t rakie-pricing:hardened   ./pricing/
docker build -t rakie-inventory:hardened ./inventory/

# K3s import (K3s does not use Docker daemon)
docker save rakie-gateway:hardened   | sudo k3s ctr images import -
docker save rakie-checkout:hardened  | sudo k3s ctr images import -
docker save rakie-pricing:hardened   | sudo k3s ctr images import -
docker save rakie-inventory:hardened | sudo k3s ctr images import -

# Deploy
kubectl set image deployment/gateway   gateway=rakie-gateway:hardened   -n rakie
kubectl set image deployment/checkout  checkout=rakie-checkout:hardened  -n rakie
kubectl set image deployment/pricing   pricing=rakie-pricing:hardened    -n rakie
kubectl set image deployment/inventory inventory=rakie-inventory:hardened -n rakie
kubectl rollout restart deployment/gateway checkout pricing inventory -n rakie
```

**Evidence:** Figures CVE-1 through CVE-6  
**Result:** CRITICAL: 0 across all 4 images. Alpine OS layer 0 vulnerabilities. axios 0.

---

## Final State — All 7 Controls Applied

| Control | Finding | Method | Evidence |
|---|---|---|---|
| NetworkPolicy | P1 | kubectl apply | FX-1, CT-6, CT-7 |
| securityContext | P4/P5 | kubectl apply | FX-2, FX-3 |
| Credentials | P6 | kubectl create (imperative) | SEC-1–SEC-5 |
| SA token | P5 | kubectl patch | SA-1–SA-4 |
| OpenSSL CVE fix | P2 | Dockerfile + rebuild | CVE-1–CVE-6 |
| axios CVE fix | P3 | Dockerfile + rebuild | CVE-1–CVE-6 |
| JSON logging | — | Code + kubectl logs | JSON-1–JSON-4 |

**Not applied:** P7 TLS — requires cert-manager infrastructure beyond manifest scope.
