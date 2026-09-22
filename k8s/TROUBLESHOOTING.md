# Kubernetes Runtime Troubleshooting Guide

This runbook applies to the ABC Technologies application in the `abc-retail`
namespace on either a local `kind` cluster or EKS.

The application intentionally runs with one replica because its DAO stores
products in process memory. Do not scale it above one replica until a shared
database or cache is introduced.

## 1. Confirm the cluster and namespace

Always verify that `kubectl` is pointed at the cluster you intend to inspect.

```bash
kubectl config current-context
kubectl config get-contexts
kubectl get namespace abc-retail
```

For a local cluster:

```bash
kubectl config use-context kind-abc-local
```

For EKS:

```bash
aws eks update-kubeconfig --name <cluster-name> --region eu-west-1
kubectl config current-context
```

`current-context` is the active cluster/user pair. A wrong context can make a
healthy deployment appear missing or cause diagnostics to target production by
mistake.

## 2. Start broad: workload status

```bash
kubectl get pods -n abc-retail -o wide
kubectl get deployment abc-retail -n abc-retail
kubectl get replicaset -n abc-retail
kubectl get service abc-retail -n abc-retail
kubectl get ingress -n abc-retail
```

Read `kubectl get pods` from left to right:

```text
NAME              READY   STATUS             RESTARTS   AGE   IP           NODE
abc-retail-...    1/1     Running            0          2m    10.0.1.12    kind-worker
```

- `NAME`: the generated Pod name.
- `READY`: ready containers divided by total containers. `1/1` means the
  readiness probe currently passes.
- `STATUS`: the high-level state that determines the next diagnostic branch.
- `RESTARTS`: container restart count. A rising value suggests crashes,
  liveness failures, or resource termination.
- `AGE`: time since the Pod was created.
- `IP`: Pod IP, useful for internal connectivity checks.
- `NODE`: the worker currently hosting the Pod.

Watch changes live:

```bash
kubectl get pods -n abc-retail -w
```

Press `Ctrl+C` to stop watching. Use the status (`Pending`,
`ImagePullBackOff`, `CrashLoopBackOff`, or `Running` but not Ready) rather
than guessing the cause.

## 3. Read Pod details and the event stream

Set a shell variable after obtaining the real Pod name:

```bash
POD=$(kubectl get pods -n abc-retail -l app=abc-retail -o jsonpath='{.items[0].metadata.name}')
echo "$POD"
```

Then inspect the Pod:

```bash
kubectl describe pod "$POD" -n abc-retail
```

Read the output in this order:

1. **Name/Namespace**: confirms the object and target namespace.
2. **Node**: shows where scheduling occurred.
3. **Labels**: compare them with the Service selector.
4. **Status/Conditions**: look for `Initialized`, `PodScheduled`,
   `ContainersReady`, and `Ready`.
5. **IP**: confirms that the Pod received network identity.
6. **Containers**: inspect image, ports, state, last state, exit code,
   restart count, resource requests/limits, and probe configuration.
7. **Events**: read the bottom section chronologically. `Reason` is the
   machine-readable category and `Message` contains the actionable detail.

Show namespace events sorted by the latest event:

```bash
kubectl get events -n abc-retail --sort-by=.lastTimestamp
```

Watch new events as they arrive:

```bash
kubectl get events -n abc-retail --watch
```

Filter events for one Pod:

```bash
kubectl get events -n abc-retail \
  --field-selector involvedObject.name="$POD" \
  --sort-by=.lastTimestamp
```

An event such as `FailedScheduling` points to node capacity, taints, or
constraints. `Pulling`, `Failed`, and `BackOff` point to image retrieval.
`Unhealthy` points to a probe failure. Events are evidence about the
control-plane decision; application behavior is usually in container logs.

## 4. `Pending` or `FailedScheduling`

Start with:

```bash
kubectl describe pod "$POD" -n abc-retail
kubectl get nodes -o wide
kubectl describe nodes
```

In the Pod event section, look for messages such as:

- `Insufficient cpu` or `Insufficient memory`: the node cannot satisfy the
  Deployment's requests (`250m` CPU and `512Mi` memory).
- `node(s) had taint`: the Pod lacks a matching toleration.
- `no nodes available`: inspect node readiness and cluster capacity.

Check requested versus allocatable capacity:

```bash
kubectl describe node <node-name>
kubectl top nodes
```

`kubectl top` requires Metrics Server. Do not confuse a resource request with
a limit: requests affect scheduling; limits cap runtime consumption.

## 5. `ImagePullBackOff` or `ErrImagePull`

Inspect the exact image and pull policy:

```bash
kubectl get pod "$POD" -n abc-retail \
  -o jsonpath='{.spec.containers[0].image}{"\n"}{.spec.containers[0].imagePullPolicy}{"\n"}'
kubectl describe pod "$POD" -n abc-retail
```

Read the event message literally. Common causes include:

- Repository or tag typo.
- Image was built locally but never loaded into kind.
- Image was never pushed to Docker Hub/ECR.
- Private registry requires an image pull secret.
- The node cannot reach the registry.

For kind, build and load the image into the same cluster:

```bash
docker build -t abc-retail-portal:latest .
kind load docker-image abc-retail-portal:latest --name abc-local
kubectl rollout restart deployment/abc-retail -n abc-retail
kubectl rollout status deployment/abc-retail -n abc-retail
```

For EKS, use a registry-qualified image and verify it exists:

```bash
kubectl set image deployment/abc-retail \
  abc-retail=<registry>/<repository>:<immutable-tag> \
  -n abc-retail
kubectl rollout status deployment/abc-retail -n abc-retail
```

For a private registry, inspect configured pull secrets:

```bash
kubectl get serviceaccount default -n abc-retail -o yaml
kubectl get secret -n abc-retail
```

Do not treat a successful local `docker images` result as proof that an EKS
node can pull the image; local Docker and cluster nodes have separate image
stores.

## 6. `CrashLoopBackOff`

Read the previous terminated container first:

```bash
kubectl logs "$POD" -n abc-retail -c abc-retail --previous
kubectl logs "$POD" -n abc-retail -c abc-retail --timestamps
kubectl describe pod "$POD" -n abc-retail
```

Why these commands matter:

- `--previous` retrieves logs from the last crashed container, not only the
  current restart attempt.
- `--timestamps` helps correlate application output with probe and event times.
- `describe` shows the last state, exit code, signal, and restart count.

Interpret the container state:

```text
Last State:     Terminated
Reason:         Error
Exit Code:      1
Restart Count:  4
```

- `Reason: Error` with exit code `1` usually means the process exited because
  of an application or startup error.
- Exit code `137` commonly indicates SIGKILL, often memory pressure or an
  enforced memory limit; confirm with events and `OOMKilled`.
- A rapidly increasing restart count means Kubernetes is repeatedly restarting
  the main process.

For this Tomcat application, inspect startup output for invalid WAR contents,
Java exceptions, port binding errors, or permission errors:

```bash
kubectl logs "$POD" -n abc-retail -c abc-retail --tail=200
```

Do not jump to `kubectl exec` when the container exits immediately: there may
be no stable process to enter. Use logs and `describe` first.

## 7. Running but not Ready

Check the readiness condition and probe events:

```bash
kubectl get pods -n abc-retail
kubectl describe pod "$POD" -n abc-retail
kubectl get endpoints abc-retail -n abc-retail
kubectl get endpointslice -n abc-retail \
  -l kubernetes.io/service-name=abc-retail
```

The current Deployment probes `/` on the named `http` port, which maps to
container port `8080`:

```yaml
readinessProbe:
  httpGet:
    path: /
    port: http
```

Typical event messages and meanings:

- `connection refused`: Tomcat is not listening yet, or the target port is
  wrong.
- `context deadline exceeded`: the application did not respond before the
  five-second timeout.
- `HTTP probe failed with statuscode: 404`: the path is wrong for the app.
- `HTTP probe failed with statuscode: 500`: the app is reachable but unhealthy.

The readiness probe has a ten-second initial delay and six allowed failures.
The liveness probe has the required twenty-second initial delay so JVM/Tomcat
startup is not mistaken for a dead process.

If readiness is false, the Service intentionally omits the Pod from its
endpoints. That is why `kubectl get endpoints` may show no addresses even
though the Pod phase is `Running`.

## 8. `OOMKilled` or memory pressure

```bash
kubectl describe pod "$POD" -n abc-retail
kubectl get pod "$POD" -n abc-retail \
  -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
kubectl top pod "$POD" -n abc-retail --containers
kubectl get events -n abc-retail --sort-by=.lastTimestamp
```

Look for:

```text
Last State:
  Terminated:
    Reason: OOMKilled
    Exit Code: 137
```

`OOMKilled` means the kernel or kubelet killed the process for exceeding its
memory limit. In this project the limit is `1Gi`. Confirm whether usage was
near the limit before changing configuration.

Check node-wide pressure:

```bash
kubectl describe node <node-name>
kubectl top nodes
```

Distinguish:

- Container limit exceeded: usually `OOMKilled` in the container state.
- Node memory pressure: node events may show eviction or pressure conditions.

Increase the limit only after checking the Java heap and workload. A larger
limit without enough node capacity can make the Pod unschedulable. Also keep
the request and limit intentional because requests affect placement.

## 9. Inspect a live container with `exec`

Only use `exec` after the Pod is running:

```bash
kubectl exec -it "$POD" -n abc-retail -c abc-retail -- sh
```

Inside the container:

```sh
id
printenv | sort
ls -la /usr/local/tomcat/webapps
ls -la /usr/local/tomcat/logs
```

- `id` verifies the hardened image is not running as root.
- `printenv` exposes runtime configuration; do not paste secrets into tickets
  or chat.
- The WAR listing confirms that `ROOT.war` was deployed.
- Logs show whether Tomcat can write to its runtime directories.

Test the local application endpoint if a suitable HTTP client exists:

```bash
kubectl exec "$POD" -n abc-retail -c abc-retail -- \
  sh -c 'wget -qO- http://127.0.0.1:8080/ | head'
```

If the image has no shell or `wget`, use port-forwarding or a temporary debug
Pod instead of modifying the production image.

## 10. Service has no traffic or is unreachable

Check labels, selectors, endpoints, and port mapping:

```bash
kubectl get pod "$POD" -n abc-retail --show-labels
kubectl get service abc-retail -n abc-retail -o yaml
kubectl get endpoints abc-retail -n abc-retail -o yaml
kubectl get endpointslice -n abc-retail \
  -l kubernetes.io/service-name=abc-retail -o yaml
```

The expected mapping is:

```text
Service port 80 → named targetPort http → container port 8080
```

If endpoints are empty:

1. Compare the Service `spec.selector` with the Pod
   `metadata.labels`.
2. Confirm the Pod is Ready; an unready Pod is excluded from endpoints.
3. Confirm the namespace is the same on both resources.

Test from inside the cluster:

```bash
kubectl run debug --rm -it --restart=Never \
  --image=busybox:1.36 -- \
  wget -qO- http://abc-retail.abc-retail.svc.cluster.local:80/
```

If the internal request succeeds, investigate Ingress or external networking.
If it fails, remain at the Service/Pod layer.

## 11. Port-forward for local isolation

Bypass Ingress and expose the Service locally:

```bash
kubectl port-forward -n abc-retail service/abc-retail 8080:80
```

In another terminal:

```bash
curl --verbose http://127.0.0.1:8080/
```

The syntax is:

```text
local-port:service-port
```

Here, local port `8080` maps to Service port `80`, which maps to the Pod’s
container port `8080`. If port-forward works, the Pod and Service path are
functional and the remaining problem is likely Ingress, DNS, security groups,
or load-balancer configuration.

You can also bypass the Service:

```bash
kubectl port-forward -n abc-retail pod/"$POD" 8080:8080
```

Use the Pod form to isolate the Service from the test. Stop port-forwarding
with `Ctrl+C`.

## 12. Ingress failures

Inspect the object and controller:

```bash
kubectl get ingress -n abc-retail
kubectl describe ingress abc-retail-nginx -n abc-retail
kubectl describe ingress abc-retail-alb -n abc-retail
```

For nginx, confirm the controller and its logs:

```bash
kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx
kubectl logs -n ingress-nginx \
  -l app.kubernetes.io/component=controller --tail=200
```

For EKS ALB, confirm the AWS Load Balancer Controller exists:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=200
```

Read the `ingressClassName` carefully:

- `nginx` requires an installed nginx controller.
- `alb` requires the AWS Load Balancer Controller and its IAM/IRSA setup.

The two manifests are environment-specific. Apply the nginx manifest to kind
and the ALB manifest to EKS; do not expect one controller to process the
other's class.

On kind, do not wait for a cloud load-balancer external IP. Use the nginx
controller's local exposure or `kubectl port-forward`.

## 13. Rollout and rollback commands

```bash
kubectl rollout status deployment/abc-retail -n abc-retail
kubectl rollout history deployment/abc-retail -n abc-retail
kubectl get rs -n abc-retail
```

If a new image or manifest is unhealthy:

```bash
kubectl rollout undo deployment/abc-retail -n abc-retail
kubectl rollout status deployment/abc-retail -n abc-retail
```

After changing only the image:

```bash
kubectl set image deployment/abc-retail \
  abc-retail=<registry>/<repository>:<immutable-tag> \
  -n abc-retail
kubectl rollout status deployment/abc-retail -n abc-retail
```

## 14. Final evidence bundle

When escalating a failure, collect these outputs while preserving the Pod
name and timestamp:

```bash
kubectl get pods -n abc-retail -o wide
kubectl describe pod "$POD" -n abc-retail
kubectl logs "$POD" -n abc-retail -c abc-retail --previous
kubectl logs "$POD" -n abc-retail -c abc-retail --tail=200
kubectl get events -n abc-retail --sort-by=.lastTimestamp
kubectl get service abc-retail -n abc-retail -o yaml
kubectl get endpoints abc-retail -n abc-retail -o yaml
kubectl get ingress -n abc-retail -o yaml
```

Redact tokens, passwords, private URLs, and other secrets before sharing logs
or command output.
