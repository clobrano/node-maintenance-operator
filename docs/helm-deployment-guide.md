# Node Maintenance Operator Helm Deployment Guide

This guide provides detailed instructions for deploying the Node Maintenance Operator using Helm charts while preserving OLM compatibility.

## Prerequisites

- Kubernetes cluster (1.19+)
- Helm 3.0+
- kubectl configured with cluster access

## Quick Start

### 1. Install with Default Settings

```bash
# Add the chart repository (once available)
helm repo add medik8s https://medik8s.github.io/helm-charts
helm repo update

# Install the operator
helm install node-maintenance-operator medik8s/node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --create-namespace
```

### 2. Install from Local Chart

```bash
# Clone the repository and navigate to helm directory
git clone https://github.com/medik8s/node-maintenance-operator-helm.git
cd node-maintenance-operator-helm/helm

# Install the chart
helm install node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --create-namespace
```

## Configuration Options

### Basic Configuration

```yaml
# values.yaml
image:
  repository: quay.io/medik8s/node-maintenance-operator
  tag: "latest"
  pullPolicy: IfNotPresent

replicaCount: 1

resources:
  limits:
    cpu: 200m
    memory: 100Mi
  requests:
    cpu: 100m
    memory: 20Mi
```

### Webhook Configuration

```yaml
webhook:
  enabled: true
  port: 9443
  failurePolicy: Fail
  timeoutSeconds: 15
  
  # Use cert-manager for automatic certificate management
  certManager:
    enabled: true
    duration: 8760h  # 1 year
    renewBefore: 360h  # 15 days
```

### Monitoring Configuration

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    additionalLabels:
      team: platform

# Enable metrics proxy for secure access
proxy:
  enabled: true
```

### OpenShift Configuration

```yaml
openshift:
  enabled: true
  scc:
    create: true
    name: "node-maintenance-operator-scc"

# OpenShift-specific tolerations and affinity
tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/infra
    operator: Exists
```

## Installation Examples

### Minimal Installation

```bash
helm install nmo ./node-maintenance-operator \
  --namespace nmo-system \
  --create-namespace \
  --set webhook.enabled=false \
  --set monitoring.enabled=false
```

⚠️ **Note**: Webhooks are disabled in this minimal setup to avoid certificate complexity. For production, enable webhooks with proper certificate management.

### Production Installation

**Prerequisites**: Install cert-manager for automatic certificate management:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s
kubectl wait --for=condition=ready pod -l app=cainjector -n cert-manager --timeout=300s
kubectl wait --for=condition=ready pod -l app=webhook -n cert-manager --timeout=300s
```

**Deploy the operator**:

```bash
helm install node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --create-namespace \
  --values - <<EOF
webhook:
  enabled: true
  certManager:
    enabled: true

monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    additionalLabels:
      prometheus: kube-prometheus

proxy:
  enabled: true

resources:
  limits:
    cpu: 500m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 64Mi

priorityClassName: system-cluster-critical

podDisruptionBudget:
  enabled: true
  minAvailable: 1
EOF
```

### OpenShift Installation

```bash
helm install node-maintenance-operator ./node-maintenance-operator \
  --namespace openshift-workload-availability \
  --create-namespace \
  --values - <<EOF
openshift:
  enabled: true

affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 3
        preference:
          matchExpressions:
            - key: node-role.kubernetes.io/infra
              operator: Exists

tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/infra
    operator: Exists

webhook:
  enabled: true
  certManager:
    enabled: true
EOF
```

## Upgrade Procedures

### Standard Upgrade

```bash
# Update chart repository
helm repo update

# Upgrade to latest version
helm upgrade node-maintenance-operator medik8s/node-maintenance-operator \
  --namespace node-maintenance-operator-system
```

### Upgrade with Value Changes

```bash
# Upgrade with new configuration
helm upgrade node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --set monitoring.enabled=true \
  --set monitoring.serviceMonitor.enabled=true
```

### Rollback

```bash
# View release history
helm history node-maintenance-operator -n node-maintenance-operator-system

# Rollback to previous version
helm rollback node-maintenance-operator -n node-maintenance-operator-system
```

## Validation and Testing

### Basic Validation

```bash
# Check operator status
kubectl get deployment -n node-maintenance-operator-system
kubectl get pods -n node-maintenance-operator-system

# Verify CRD installation
kubectl get crd nodemaintenances.nodemaintenance.medik8s.io

# Check webhook configuration
kubectl get validatingwebhookconfiguration
```

### Functional Testing

```bash
# Get a worker node name
NODE_NAME=$(kubectl get nodes --no-headers -o custom-columns=":metadata.name" | grep -v master | head -1)

# Create a test NodeMaintenance
cat <<EOF | kubectl apply -f -
apiVersion: nodemaintenance.medik8s.io/v1beta1
kind: NodeMaintenance
metadata:
  name: test-maintenance
spec:
  nodeName: $NODE_NAME
  reason: "Testing node maintenance operator"
EOF

# Monitor the maintenance process
kubectl get nodemaintenance test-maintenance -w

# Check node status
kubectl get node $NODE_NAME

# Clean up
kubectl delete nodemaintenance test-maintenance
kubectl uncordon $NODE_NAME
```

### Automated Testing

Use the provided test script:

```bash
# Run comprehensive test suite
./test-deployment.sh \
  --namespace nmo-test \
  --release-name test-nmo \
  --chart-path ./node-maintenance-operator
```

## Uninstallation

### Standard Uninstall

```bash
# Uninstall the Helm release
helm uninstall node-maintenance-operator \
  --namespace node-maintenance-operator-system

# Remove CRDs (if desired)
kubectl delete crd nodemaintenances.nodemaintenance.medik8s.io

# Remove namespace
kubectl delete namespace node-maintenance-operator-system
```

### Complete Cleanup

```bash
# Remove all NodeMaintenance resources first
kubectl delete nodemaintenance --all --all-namespaces

# Uncordon any nodes that might be cordoned
kubectl get nodes -o jsonpath='{.items[?(@.spec.unschedulable==true)].metadata.name}' | xargs -r kubectl uncordon

# Uninstall the operator
helm uninstall node-maintenance-operator -n node-maintenance-operator-system

# Clean up cluster resources
kubectl delete crd nodemaintenances.nodemaintenance.medik8s.io
kubectl delete clusterrole node-maintenance-operator-*
kubectl delete clusterrolebinding node-maintenance-operator-*
kubectl delete validatingwebhookconfiguration node-maintenance-operator-*

# Remove namespace
kubectl delete namespace node-maintenance-operator-system
```

## Webhook Certificate Management

The Node Maintenance Operator uses admission webhooks for validation. When webhooks are enabled, TLS certificates are required.

### Option 1: Disable Webhooks (Testing/Development)

```bash
helm install node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --create-namespace \
  --set webhook.enabled=false
```

### Option 2: Use cert-manager (Recommended)

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s

# Deploy with cert-manager integration
helm install node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --create-namespace \
  --set webhook.enabled=true \
  --set webhook.certManager.enabled=true
```

### Option 3: Manual Certificate Management

```bash
# Create namespace
kubectl create namespace node-maintenance-operator-system --dry-run=client -o yaml | kubectl apply -f -

# Generate self-signed certificate
openssl req -x509 -newkey rsa:4096 -keyout tls.key -out tls.crt -days 365 -nodes \
  -subj "/CN=node-maintenance-operator-webhook-service.node-maintenance-operator-system.svc" \
  -addext "subjectAltName=DNS:node-maintenance-operator-webhook-service.node-maintenance-operator-system.svc,DNS:node-maintenance-operator-webhook-service.node-maintenance-operator-system.svc.cluster.local"

# Create the certificate secret
kubectl create secret tls node-maintenance-operator-webhook-server-cert \
  --cert=tls.crt --key=tls.key \
  -n node-maintenance-operator-system

# Clean up certificate files
rm tls.key tls.crt

# Deploy the operator
helm install node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --create-namespace \
  --set webhook.enabled=true \
  --set webhook.certManager.enabled=false
```

## Troubleshooting

### Common Issues

#### 1. Pod Stuck in ContainerCreating - Missing Webhook Certificate

**Symptoms**: 
```
Warning  FailedMount  kubelet  MountVolume.SetUp failed for volume "cert" : secret "node-maintenance-operator-webhook-server-cert" not found
```

**Solutions**:
```bash
# Option A: Disable webhooks and redeploy
helm uninstall node-maintenance-operator -n node-maintenance-operator-system
helm install node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --create-namespace \
  --set webhook.enabled=false

# Option B: Install cert-manager and enable it
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s
helm upgrade node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --set webhook.certManager.enabled=true

# Option C: Create manual certificate (see Manual Certificate Management above)
```

#### 2. Webhook Certificate Issues

```bash
# Check certificate status
kubectl get certificate -n node-maintenance-operator-system
kubectl describe certificate -n node-maintenance-operator-system

# Recreate certificate (if using cert-manager)
kubectl delete certificate serving-cert -n node-maintenance-operator-system
helm upgrade node-maintenance-operator ./node-maintenance-operator -n node-maintenance-operator-system --reuse-values
```

#### 2. Operator Not Starting

```bash
# Check pod logs
kubectl logs -n node-maintenance-operator-system deployment/node-maintenance-operator-controller-manager

# Check events
kubectl get events -n node-maintenance-operator-system --sort-by='.lastTimestamp'

# Verify RBAC
kubectl auth can-i '*' '*' --as=system:serviceaccount:node-maintenance-operator-system:node-maintenance-operator-controller-manager
```

#### 3. NodeMaintenance Resources Not Processing

```bash
# Check operator logs
kubectl logs -n node-maintenance-operator-system -l control-plane=controller-manager -f

# Verify CRD status
kubectl get crd nodemaintenances.nodemaintenance.medik8s.io -o yaml

# Check NodeMaintenance resource status
kubectl get nodemaintenance -o yaml
```

### Debug Mode

Enable debug logging:

```bash
helm upgrade node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --set operator.args="{--leader-elect,--v=2}"
```

## Migration from OLM

If you have an existing OLM-based installation:

### 1. Backup Current State

```bash
# Backup existing NodeMaintenance resources
kubectl get nodemaintenance -o yaml > nodemaintenance-backup.yaml

# Note cordoned nodes
kubectl get nodes -o jsonpath='{.items[?(@.spec.unschedulable==true)].metadata.name}' > cordoned-nodes.txt
```

### 2. Remove OLM Installation

```bash
# Remove the operator subscription and CSV
kubectl delete subscription node-maintenance-operator -n openshift-operators
kubectl delete csv $(kubectl get csv -n openshift-operators -o name | grep node-maintenance-operator) -n openshift-operators
```

### 3. Install via Helm

```bash
# Install using Helm with the same configuration
helm install node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --create-namespace \
  --set webhook.enabled=true
```

### 4. Restore State

```bash
# Restore NodeMaintenance resources
kubectl apply -f nodemaintenance-backup.yaml

# Verify cordoned nodes are still cordoned
while read node; do kubectl cordon $node; done < cordoned-nodes.txt
```

## Best Practices

### 1. Production Deployment

- Use specific image tags instead of `latest`
- Enable monitoring and alerting
- Configure appropriate resource limits
- Use PodDisruptionBudgets for high availability
- Enable webhook validation

### 2. Security

- Enable RBAC (default)
- Use least-privilege service accounts
- Enable Pod Security Standards/Policies
- Regularly update to latest versions

### 3. Monitoring

- Enable ServiceMonitor for Prometheus
- Monitor operator health and performance
- Set up alerts for failed node maintenance operations
- Track node maintenance duration and success rates

### 4. Backup and Recovery

- Regularly backup NodeMaintenance resources
- Document node maintenance procedures
- Test disaster recovery scenarios
- Keep track of cordoned nodes

## Integration with CI/CD

### GitOps Integration

```yaml
# ArgoCD Application example
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: node-maintenance-operator
  namespace: argocd
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/medik8s/node-maintenance-operator-helm
    path: helm/node-maintenance-operator
    targetRevision: main
    helm:
      valueFiles:
        - values-production.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: node-maintenance-operator-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Flux Integration

```yaml
# HelmRelease example
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: node-maintenance-operator
  namespace: flux-system
spec:
  interval: 10m
  chart:
    spec:
      chart: node-maintenance-operator
      sourceRef:
        kind: HelmRepository
        name: medik8s
        namespace: flux-system
      interval: 1m
  targetNamespace: node-maintenance-operator-system
  install:
    createNamespace: true
  values:
    webhook:
      enabled: true
    monitoring:
      enabled: true
``` 