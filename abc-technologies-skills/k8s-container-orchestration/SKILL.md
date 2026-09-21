---
name: k8s-container-orchestration
description: Writes and reviews the full set of Kubernetes manifests for deploying and scaling an app — Namespace, Deployment, Service, Ingress, HPA, PV/PVC — and decides which ones a given app actually needs. Use whenever the user is deploying an app to Kubernetes, exposing a service, setting up autoscaling or ingress, or asks "what manifests do I need" for a workload.
---

Decide manifests in this order — each one's correctness depends on the one before it.

## 1. Namespace
Isolate the app into its own namespace before writing anything else. Every other manifest in this app targets that namespace explicitly (`metadata.namespace` or `-n` at apply time), not `default`.

## 2. Deployment
- **Replica count is a data-shape decision, not a default.** If the app keeps state in memory (no shared/external datastore), running more than 1 replica silently causes inconsistent reads/writes across pods — start at `replicas: 1` and only raise it once a real shared datastore backs the app. Don't default to 2+ for "high availability" without checking this first.
- Set `resources.requests` and `resources.limits` on every container — HPA (below) cannot function without requests being set, and unset limits let one runaway pod starve the node.
- Add `readinessProbe` and `livenessProbe` — readiness gates traffic (via the Service), liveness triggers restarts. Don't reuse the same endpoint/threshold for both without thinking about it: a slow-starting app needs a lenient liveness `initialDelaySeconds` or it will be killed before it finishes starting.
- Pin `imagePullPolicy` deliberately: `IfNotPresent` for tagged images in production, `Always` only if you're actively iterating on a mutable tag during local/kind testing.

## 3. Service
- `selector` labels must match the Deployment's pod template labels *exactly* — this is the single most common misconfiguration and produces a Service with zero endpoints and no error message.
- Default to `ClusterIP` for internal traffic; only use `LoadBalancer`/`NodePort` when the app must be reachable from outside the cluster and there's no Ingress in front of it.

## 4. Ingress — environment-specific, don't share one manifest
Local (kind) and real cloud (EKS) need different ingress controllers and should be **separate manifest files**, not one file toggled with comments:
- Local/kind: `nginx-ingress` controller, simpler annotations, works without cloud load balancer provisioning.
- Production EKS: AWS Load Balancer Controller, different `ingressClassName`/annotations, provisions a real ALB.
Keep both files in the repo (e.g. `ingress-nginx.yaml`, `ingress-alb.yaml`) and apply the one matching the current target cluster.

## 5. HPA (Horizontal Pod Autoscaler)
- Requires `resources.requests` on the Deployment (step 2) — without it, HPA has nothing to calculate utilization against and will silently fail to scale.
- Set `minReplicas`/`maxReplicas` based on the same statefulness consideration as step 2 — don't let HPA scale a single-replica-only app past 1 until the datastore constraint is resolved.

## 6. PV / PVC — only if the app actually persists data
Don't add these by default. Check whether the app's data access layer is actually backed by a real store or just an in-memory structure — many course/demo apps use an in-memory map and don't need persistent storage at all. If storage genuinely is needed: pick a `storageClassName` appropriate to the cluster (a local `hostPath`/`kind` provisioner for local testing vs. an EBS-backed class on EKS), and match `accessModes` to how many pods will mount it (`ReadWriteOnce` for single-pod, `ReadWriteMany` needs a filesystem that supports it).

## 7. Apply order
`namespace` → `pv`/`pvc` (if needed) → `deployment` → `service` → `hpa` → `ingress`. Applying Service or Ingress before the Deployment exists is harmless (they'll just have no endpoints yet), but applying HPA before Deployment resource requests are set is the common failure point — always confirm step 2 is complete first.

## 8. Label consistency
Keep one label set (`app`, `tier`, `environment`) applied identically across Deployment pod template, Service selector, and HPA target — a mismatch anywhere in this chain breaks routing or scaling silently, with no error surfaced by `kubectl apply`.
