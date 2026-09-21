---
name: k8s-troubleshooting-debugging
description: Diagnoses failing Kubernetes pods, deployments, services, and ingress — CrashLoopBackOff, ImagePullBackOff, Pending pods, failed probes, unreachable services, HPA not scaling. Use whenever a pod won't start, a rollout is stuck, a service can't be reached, or the user needs to debug cluster/application behavior with kubectl. Push to use this skill even if the user just pastes an error or a pod status without asking to "debug."
---

Work top-down: start broad, then narrow based on what the status actually says. Don't jump straight to `kubectl exec` before checking `describe`/`logs`.

## 1. Start broad
```
kubectl get pods -n <namespace> -o wide
```
The `STATUS` column decides the next step — don't guess before looking at it.

## 2. Route by STATUS

**Pending**
→ `kubectl describe pod <pod> -n <namespace>`, read the `Events` section. Common causes: no node has enough allocatable resources for the requested `resources.requests`, an unbound PVC, or a node selector/affinity rule nothing matches.

**ImagePullBackOff / ErrImagePull**
→ Check the exact image name and tag for typos, confirm the image actually exists in the registry, and check `imagePullSecrets` if it's a private registry. A tag that exists locally but was never pushed is the most common cause in CI/CD pipelines.

**CrashLoopBackOff**
→ `kubectl logs <pod> -n <namespace> --previous` (the crashed instance's logs, not the current restart attempt). Check the exit code in `kubectl describe pod` output. Common causes: missing required env var/config, the app tries to bind a port already in use, or a startup dependency (DB, another service) isn't reachable yet.

**Running but never Ready**
→ Check the `readinessProbe` config against what the app actually exposes (path, port, initial delay). `kubectl describe pod` will show probe failure events with the actual HTTP status/error returned.

## 3. Service unreachable (pods are Running/Ready but traffic doesn't get there)
1. `kubectl get endpoints <service> -n <namespace>` — if empty, the Service's `selector` doesn't match the pod labels. Compare them directly; don't assume they match because the manifests "look right."
2. If endpoints exist, check `targetPort` on the Service actually matches the container's listening port (not just the Service's own external `port`).
3. Test from inside the cluster first (`kubectl run -it --rm debug --image=busybox -- wget -qO- <service>.<namespace>.svc.cluster.local:<port>`) before assuming an external/Ingress-layer problem.

## 4. Ingress issues
- Confirm `ingressClassName` matches an actually-installed controller — a mismatched class means the ingress object exists but no controller is watching it, with no error surfaced.
- Check the controller's own logs (`kubectl logs -n <controller-namespace> <controller-pod>`), not just the Ingress object's events.
- On `kind`/local clusters, `LoadBalancer`-type Services never get an external IP by design — that's expected, not a bug; use `kubectl port-forward` or a NodePort for local access instead of waiting on an IP that won't appear.

## 5. HPA not scaling
- Confirm `metrics-server` is installed and running in the cluster (`kubectl top pods` should return numbers, not an error).
- Confirm the target Deployment has `resources.requests` set — HPA can't compute utilization without them.

## 6. General toolbox (reach for these anytime the above doesn't pinpoint it)
```
kubectl describe <resource> <name> -n <namespace>
kubectl logs <pod> -n <namespace> [-c <container>] [--previous]
kubectl exec -it <pod> -n <namespace> -- sh
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

## 7. Local vs. real-cluster gotchas
Before concluding something is broken, rule out these environment differences between `kind` and a real EKS cluster: `LoadBalancer` IPs (never appear on kind), default `storageClassName` (kind's provisioner name differs from EBS-backed classes on EKS), and ingress controller type (nginx locally vs. ALB controller on EKS) — a manifest correct for one will legitimately behave differently, not incorrectly, on the other.
