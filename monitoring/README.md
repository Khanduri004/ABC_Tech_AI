# Production monitoring

## Recommended architecture

Use the `prometheus-community/kube-prometheus-stack` Helm chart instead of
maintaining separate raw Deployments for Prometheus, Grafana, and Alertmanager.
The chart packages and wires together:

- Prometheus Operator and custom resources
- Prometheus and Kubernetes service discovery
- Alertmanager
- Grafana with Kubernetes dashboards
- kube-state-metrics
- node-exporter
- Curated Kubernetes alert rules

This is the operationally safer production pattern because upgrades, selectors,
RBAC, service discovery, and component compatibility are maintained as one
versioned release. Pin the chart version in CI/CD and review upgrades rather
than installing an unbounded `latest`.

The application currently exposes no Prometheus `/metrics` endpoint. The rules
in `prometheus-rules.yaml` therefore monitor Kubernetes-level availability,
restarts, and memory usage. Add Micrometer or another instrumentation library
before creating an application `ServiceMonitor`; scraping the current HTML
root page as Prometheus metrics would be invalid.

## EKS installation

Run these commands from a workstation or Jenkins agent with cluster-admin
permissions. The example pins chart version `91.4.1`; review this version in a
non-production cluster before promoting it:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm search repo prometheus-community/kube-prometheus-stack --versions
```

Create the EKS storage class required by the values file if it is not already
installed:

```bash
kubectl get storageclass gp3
```

Create the Grafana admin secret without putting its password in Git:

```bash
kubectl create namespace monitoring
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<generate-a-long-random-password>'
```

Install or upgrade the stack with a reviewed chart version:

```bash
helm upgrade --install abc-monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --version 91.4.1 \
  --values monitoring/kube-prometheus-stack-values.yaml \
  --wait \
  --timeout 10m
```

Apply the project alerts after the operator CRDs exist:

```bash
kubectl apply -f monitoring/prometheus-rules.yaml
```

The values use the EKS `gp3` StorageClass for Prometheus, Alertmanager, and
Grafana persistence. Confirm the EBS CSI driver is installed and that its
nodes have the required IAM permissions before installation.

## Alert notifications

Alertmanager is enabled, but production notifications must be configured with
a secret-managed receiver. Do not commit SMTP passwords, Slack webhooks, or
PagerDuty tokens. Use an external secret manager, Sealed Secret, or a
Jenkins/Kubernetes secret workflow to create the Alertmanager secret, then
configure the chart's `alertmanager.config` or `alertmanagerConfig` resource.

At minimum, route `critical` alerts to an on-call destination and keep a
lower-priority route for warnings. Test notification delivery with a deliberate
temporary alert before relying on it operationally.

## Secure access

The services intentionally remain `ClusterIP`; they are not public Internet
endpoints. Use port-forwarding for administration:

```bash
kubectl -n monitoring port-forward service/abc-monitoring-grafana 3000:80
kubectl -n monitoring port-forward service/abc-monitoring-prometheus 9090:9090
kubectl -n monitoring port-forward service/abc-monitoring-alertmanager 9093:9093
```

Then browse:

- Grafana: http://127.0.0.1:3000
- Prometheus: http://127.0.0.1:9090
- Alertmanager: http://127.0.0.1:9093

For a shared production UI, put Grafana behind the existing authenticated
ingress or an internal ALB with TLS, SSO, and network restrictions. Do not
make Prometheus or Alertmanager public without authentication and authorization.

## Validation and operations

```bash
kubectl -n monitoring get pods
kubectl -n monitoring get pvc
kubectl -n monitoring get prometheus,alertmanager,prometheusrule
kubectl -n monitoring get servicemonitors
helm -n monitoring list
```

Check the Prometheus targets page and confirm `kube-state-metrics`,
node-exporter, the Kubernetes API, and kubelet targets are healthy.

For kind, use a separate values override because the EKS `gp3` StorageClass
may not exist:

```bash
helm upgrade --install abc-monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --version 91.4.1 \
  --values monitoring/kube-prometheus-stack-values.yaml \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName="" \
  --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.storageClassName="" \
  --set grafana.persistence.storageClassName="" \
  --wait
```

The application remains at one replica because its data store is in memory;
monitoring does not change that constraint.
