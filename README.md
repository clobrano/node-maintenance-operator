# Node Maintenance Operator (NMO)

<p align="center">
<img width="100" src="config/assets/nmo_blue_icon.png">
</p>

The node-maintenance-operator (**NMO**) is an operator generated from the [operator-sdk](https://github.com/operator-framework/operator-sdk).
NMO was *previously* developed under [KubeVirt](https://github.com/kubevirt/node-maintenance-operator), and this repository is the up-to-date version of NMO.

The purpose of this operator is to watch for new or deleted custom resources (CRs) called `NodeMaintenance` which indicate that a node in the cluster should either:
  - `NodeMaintenance` CR created: move node into maintenance, cordon the node - set it as unschedulable, and evict the pods (which can be evicted) from that node.
  - `NodeMaintenance` CR deleted: remove node from maintenance and uncordon the node - set it as schedulable.

> *Note*:  The current behavior of the operator is to mimic `kubectl drain <node name>`.

## Deployment Options

The Node Maintenance Operator can be deployed using two methods:

### 1. Helm Charts (Recommended for Kubernetes)

The Helm chart provides flexible configuration options and better integration with GitOps workflows.

#### Quick Start with Helm

```bash
# Install from local chart
git clone https://github.com/medik8s/node-maintenance-operator-helm.git
cd node-maintenance-operator-helm/helm

# Simple installation (webhooks disabled for quick testing)
helm install node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --create-namespace \
  --set webhook.enabled=false

# For production with webhooks, install cert-manager first:
# kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
# kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s
# Then: --set webhook.enabled=true --set webhook.certManager.enabled=true
```

#### Features

- ✅ Flexible configuration via values.yaml
- ✅ GitOps-friendly (ArgoCD, Flux)
- ✅ Version management and rollbacks
- ✅ Optional webhook validation
- ✅ Monitoring integration (Prometheus)
- ✅ cert-manager integration
- ✅ OpenShift compatibility

📖 **[Complete Helm Deployment Guide](docs/helm-deployment-guide.md)**

### 2. OLM (Operator Lifecycle Manager)

Traditional deployment method for OpenShift and OLM-enabled clusters.

#### Deploy the latest version

After every PR merge to `main` branch images were build and pushed to `quay.io`.
For deployment of NMO using these images you need:

- a running OpenShift cluster, or a Kubernetes cluster with Operator Lifecycle Manager (OLM) installed.
- `operator-sdk` binary installed, see https://sdk.operatorframework.io/docs/installation/.
- a valid `$KUBECONFIG` configured to access your cluster.

Then run `operator-sdk run bundle quay.io/medik8s/node-maintenance-operator-bundle:latest`

#### Deploy the last release version
Click on `Install` in the Node Maintenance Operator page under [OperatorHub.io](https://operatorhub.io/operator/node-maintenance-operator), 
and follow its instructions to install the [Operator Lifecycle Manager (OLM)](https://olm.operatorframework.io/), and the operator.

#### Build and deploy from sources
Follow the instructions [here](https://sdk.operatorframework.io/docs/building-operators/golang/tutorial/#3-deploy-your-operator-with-olm) for deploying the operator with OLM.
> *Note*: Webhook cannot run using `make deploy`, because the volume mount of the webserver certificate is not found.

## Local Development and Testing

### Setting up a Test Cluster

📖 **[Local Testing Setup Guide](docs/local-testing-setup.md)** - Comprehensive guide for setting up local clusters with kind, minikube, or k3d.

### Automated Testing

```bash
# Run comprehensive Helm chart tests
./helm/test-deployment.sh --namespace nmo-test --release-name test-nmo
```

## Setting Node Maintenance

### Set Maintenance on - Create a NodeMaintenance CR

To set maintenance on a node a `NodeMaintenance` custom resource should be created.
The `NodeMaintenance` CR spec contains:
- nodeName: The name of the node which will be put into maintenance mode.
- reason: The reason why the node will be under maintenance.

Example:

```yaml
apiVersion: nodemaintenance.medik8s.io/v1beta1
kind: NodeMaintenance
metadata:
  name: nodemaintenance-node02
spec:
  nodeName: node02
  reason: "Testing node maintenance"
```

### Set Maintenance off - Delete the NodeMaintenance CR

To remove maintenance from a node, the `NodeMaintenance` custom resource should be deleted.

Example:

```bash
kubectl delete nodemaintenance nodemaintenance-node02
```

### NodeMaintenance CR Status

User can query the NodeMaintenance CR status as follows:

```bash
kubectl get nodemaintenance nodemaintenance-node02 -o yaml
```

For detailed status information see `status` section in the CR:

```yaml
status:
  drainProgress: 100
  evictionPods: 3
  lastError: ""
  lastUpdate: "2021-09-22T08:13:43Z"
  pendingPods: 
  phase: Succeeded
  totalpods: 3
```

## Configuration

### Helm Configuration

The Helm chart supports extensive configuration options:

```yaml
# Example values.yaml
webhook:
  enabled: true
  certManager:
    enabled: true

monitoring:
  enabled: true
  serviceMonitor:
    enabled: true

resources:
  limits:
    cpu: 200m
    memory: 100Mi
  requests:
    cpu: 100m
    memory: 20Mi

# OpenShift specific settings
openshift:
  enabled: true
```

See [helm/node-maintenance-operator/values.yaml](helm/node-maintenance-operator/values.yaml) for all available options.

## Migration from OLM to Helm

If you're currently using OLM deployment and want to migrate to Helm:

📖 **[Migration Guide](docs/helm-deployment-guide.md#migration-from-olm)** - Step-by-step migration instructions.

## Troubleshooting

### Common Issues

1. **Webhook certificate issues**: See [troubleshooting guide](docs/helm-deployment-guide.md#troubleshooting)
2. **Node not being cordoned**: Check operator logs and RBAC permissions
3. **Pods not evicting**: Verify PodDisruptionBudgets and pod deletion policies

### Debug Information

```bash
# Check operator status
kubectl get deployment -n node-maintenance-operator-system
kubectl logs -n node-maintenance-operator-system -l control-plane=controller-manager

# Check NodeMaintenance resources
kubectl get nodemaintenance -o yaml
kubectl describe nodemaintenance <name>
```

## Contributing

1. Fork the repository
2. Create your feature branch
3. Add tests for new functionality
4. Ensure all tests pass: `./helm/test-deployment.sh`
5. Submit a pull request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Community

- **GitHub Issues**: [Report bugs and request features](https://github.com/medik8s/node-maintenance-operator/issues)
- **Slack**: Join us in the [#medik8s channel](https://kubernetes.slack.com/channels/medik8s) on Kubernetes Slack
- **Documentation**: [Project Wiki](https://github.com/medik8s/node-maintenance-operator/wiki)

## Related Projects

- [Self Node Remediation](https://github.com/medik8s/self-node-remediation) - Automatic node remediation
- [Node Healthcheck Operator](https://github.com/medik8s/node-healthcheck-operator) - Node health monitoring
- [Poison Pill](https://github.com/medik8s/poison-pill) - Node failure detection and remediation
