# Observability Implementation

> EAD CA2 · Rakesh Uday Kumar (A00047386) · TU Dublin · May 2026

---

## What Was Added

Two observability layers were added to the CA1 platform:

1. **Structured JSON logging** on all 4 services — requestId propagation via X-Request-Id
2. **kube-prometheus-stack** — Prometheus, Grafana, AlertManager in isolated namespace

---

## Structured JSON Log Format

Every service emits structured JSON to stdout on every request:

```json
{
  "timestamp": "2026-05-21T15:13:26.993Z",
  "level": "info",
  "service": "checkout",
  "requestId": "ca2-obs-1",
  "method": "POST",
  "path": "/checkout",
  "status": 200,
  "durationMs": 787
}
```

**Fields:**
- `timestamp` — ISO 8601, enables time-based correlation
- `level` — info / error (level:error with errorCode on failures)
- `service` — which of the 4 services emitted this log
- `requestId` — X-Request-Id header propagated from gateway through all services
- `method` / `path` — what was called
- `status` — HTTP status code
- `durationMs` — end-to-end processing time for this service

**Why this matters:** Under concurrent traffic, log lines from multiple requests interleave. Without requestId, correlating a failure across 4 services requires timestamp matching — unreliable. With requestId, a single `kubectl logs | grep ca2-obs-1` shows the complete trace.

---

## Service Timeouts

| Service Call | Timeout | Rationale |
|---|---|---|
| checkout → pricing | 5s | pricing always-on; covers normal jitter |
| checkout → inventory | 5s | same profile as pricing |
| checkout → postgres | 3s | in-cluster DB; slow query should fail fast |
| gateway → checkout | 30s | covers KEDA cold-start + full processing |

---

## Prometheus + Grafana Installation

```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=32000
```

**Result:**
- 6 monitoring pods running in `monitoring` namespace
- 13 ServiceMonitors active
- 35 PrometheusRules active
- Grafana dashboard at `http://<VM-IP>:32000` (admin / prom-operator)

---

## Observability Scenario — Inventory Service Failure

### State 1 — Healthy Baseline

```bash
curl -s -X POST http://localhost:30080/api/checkout \
  -H "X-Request-Id: ca2-healthy" \
  -H "Content-Type: application/json" \
  -d '{"sku":"SKU-001","qty":1}'
# Returns: {"status":"confirmed","orderId":128}

kubectl logs -n rakie deploy/checkout --tail=5
kubectl logs -n rakie deploy/gateway  --tail=3
```

All services show status:200 with durationMs within thresholds. This baseline makes anomalies immediately identifiable.

### State 2 — Failure Induced

```bash
# Scale inventory to 0
kubectl scale deployment inventory --replicas=0 -n rakie
kubectl get pods -n rakie  # inventory shows Terminating

# Send requests — all 503
for i in $(seq 1 5); do
  curl -s -X POST http://localhost:30080/api/checkout \
    -H "X-Request-Id: ca2-obs-$i" \
    -H "Content-Type: application/json" \
    -d '{"sku":"SKU-001","qty":1}'
done
```

### 3-Step Diagnosis

```bash
# Step 1: gateway shows 503 for ca2-obs-1
kubectl logs -n rakie deploy/gateway | grep "ca2-obs-1"
# output: level:error, status:503, upstream error

# Step 2: checkout shows ECONNREFUSED on inventory-svc:3003
kubectl logs -n rakie deploy/checkout | grep "ca2-obs-1"
# output: level:error, errorCode:ECONNREFUSED, service:inventory-svc:3003

# Step 3: pod list confirms inventory at 0/0
kubectl get pods -n rakie | grep inventory
# output: inventory-xxx 0/0 Running
```

Root cause identified — inventory pod down — in under 60 seconds using only `kubectl logs`.

### State 3 — Recovery

```bash
kubectl scale deployment inventory --replicas=1 -n rakie
sleep 15 && kubectl get pods -n rakie  # all 5 pods 1/1 Running

curl -s -X POST http://localhost:30080/api/checkout \
  -H "X-Request-Id: ca2-recover-1" \
  -H "Content-Type: application/json" \
  -d '{"sku":"SKU-001","qty":1}'
# Returns: {"status":"confirmed","orderId":141}
```

System recovered within 15 seconds. No manual intervention beyond scaling back.

---

## Why This Approach Works Without a Service Mesh

Standard distributed tracing (Jaeger, Zipkin, OpenTelemetry) requires sidecar injection or SDK instrumentation. The X-Request-Id approach achieves cross-service correlation with:

- A single UUID generated at the gateway per request
- Propagation via HTTP header to all downstream calls
- JSON structured logging that indexes the requestId field

The result is functionally equivalent for diagnosis: given a failing requestId, `kubectl logs | grep <requestId>` shows the complete trace across all services in the correct sequence.
