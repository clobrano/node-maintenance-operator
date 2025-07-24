# Local Testing Setup for Node Maintenance Operator

This document provides instructions for setting up a local Kubernetes cluster to test the Node Maintenance Operator deployment via Helm.

## Prerequisites

- Docker installed and running
- kubectl installed
- Helm 3.x installed (see installation instructions below)

## Install Helm

Helm is required for deploying the Node Maintenance Operator via the Helm chart.

### Linux

```bash
# Download and install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Or using package managers:
# Ubuntu/Debian
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

# Fedora/RHEL/CentOS
sudo dnf install helm
```

### macOS

```bash
# Using Homebrew (recommended)
brew install helm

# Or using the install script
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

### Windows

```powershell
# Using Chocolatey
choco install kubernetes-helm

# Using Scoop
scoop install helm

# Or download from GitHub releases
# https://github.com/helm/helm/releases
```

### Verify Installation

```bash
helm version
# Should output something like: version.BuildInfo{Version:"v3.x.x", ...}

# Add completion (optional but helpful)
echo 'source <(helm completion bash)' >> ~/.bashrc  # For bash
echo 'source <(helm completion zsh)' >> ~/.zshrc    # For zsh
```

## Option 1: Kind (Recommended)

Kind (Kubernetes in Docker) is the recommended option as it provides excellent webhook support and cluster configuration flexibility.

### Installation

```bash
# Install kind
GO111MODULE="on" go install sigs.k8s.io/kind@latest

# Or using package managers:
# macOS: brew install kind
# Linux: curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/
```

### Create Test Cluster

```bash
# Create kind configuration for webhook support
cat << EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: nmo-test
nodes:
- role: control-plane
  image: kindest/node:v1.28.0
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
  image: kindest/node:v1.28.0
- role: worker
  image: kindest/node:v1.28.0
EOF

# Create the cluster
kind create cluster --config kind-config.yaml

# Verify cluster
kubectl cluster-info --context kind-nmo-test
kubectl get nodes
```

## Option 2: Minikube

Minikube provides good local development experience with add-on support.

### Installation and Setup

```bash
# Install minikube (if not already installed)
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Start minikube with sufficient resources
minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=8192 \
  --kubernetes-version=v1.28.0 \
  --profile=nmo-test

# Enable required add-ons
minikube addons enable metrics-server -p nmo-test

# Verify setup
kubectl config use-context minikube
kubectl get nodes
```

## Option 3: K3d

K3d is a lightweight wrapper around K3s and provides fast cluster creation.

### Installation and Setup

```bash
# Install k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Create cluster
k3d cluster create nmo-test \
  --agents 2 \
  --k3s-arg "--disable=traefik@server:0" \
  --port "8080:80@loadbalancer" \
  --port "8443:443@loadbalancer"

# Verify setup
kubectl config use-context k3d-nmo-test
kubectl get nodes
```

## Testing Webhook Support

Regardless of the chosen option, verify that webhook functionality works:

```bash
# Test webhook admission controllers
kubectl create -f - << EOF
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: test-webhook
webhooks:
- name: test-webhook.example.com
  clientConfig:
    service:
      name: test-service
      namespace: default
      path: "/validate"
  rules:
  - operations: ["CREATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  admissionReviewVersions: ["v1", "v1beta1"]
  sideEffects: None
  failurePolicy: Fail
EOF

# Clean up test webhook
kubectl delete validatingwebhookconfiguration test-webhook
```

## Load Testing Images

For faster testing, pre-load the operator image:

```bash
# For kind
docker pull quay.io/medik8s/node-maintenance-operator:latest
kind load docker-image quay.io/medik8s/node-maintenance-operator:latest --name nmo-test

# For minikube
minikube image load quay.io/medik8s/node-maintenance-operator:latest -p nmo-test

# For k3d
k3d image import quay.io/medik8s/node-maintenance-operator:latest -c nmo-test
```

## Cluster Cleanup

```bash
# Kind
kind delete cluster --name nmo-test

# Minikube
minikube delete -p nmo-test

# K3d
k3d cluster delete nmo-test
```

## Recommended Setup Script

Create a quick setup script for repeated testing:

```bash
#!/bin/bash
# setup-test-cluster.sh

set -e

CLUSTER_NAME="nmo-test"
CLUSTER_TYPE=${1:-"kind"} # kind, minikube, or k3d

echo "Setting up $CLUSTER_TYPE cluster: $CLUSTER_NAME"

case $CLUSTER_TYPE in
  "kind")
    # Kind setup with webhook support
    cat << EOF > /tmp/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: $CLUSTER_NAME
nodes:
- role: control-plane
  image: kindest/node:v1.28.0
- role: worker
  image: kindest/node:v1.28.0
- role: worker
  image: kindest/node:v1.28.0
EOF
    kind create cluster --config /tmp/kind-config.yaml
    ;;
  "minikube")
    minikube start --driver=docker --cpus=4 --memory=8192 --kubernetes-version=v1.28.0 --profile=$CLUSTER_NAME
    ;;
  "k3d")
    k3d cluster create $CLUSTER_NAME --agents 2
    ;;
  *)
    echo "Unsupported cluster type: $CLUSTER_TYPE"
    exit 1
    ;;
esac

echo "Cluster $CLUSTER_NAME created successfully!"
kubectl get nodes
```

Make it executable and use:

```bash
chmod +x setup-test-cluster.sh
./setup-test-cluster.sh kind
```

## Next Steps

Once you have completed the cluster setup and loaded the testing images, you're ready to deploy the Node Maintenance Operator.

### Continue with Operator Deployment

📖 **[Helm Deployment Guide](helm-deployment-guide.md)** - Follow this comprehensive guide for:

- **Quick Start Installation**: Simple one-command deployment
- **Production Installation**: Full configuration with monitoring and webhooks  
- **Custom Configuration**: Detailed values.yaml customization
- **Validation and Testing**: Step-by-step verification procedures

### Quick Deployment Command

For immediate testing, you can deploy the operator with:

```bash
# Navigate to helm directory
cd helm

# Option 1: Deploy without webhooks (fastest for testing)
helm install node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --create-namespace \
  --set webhook.enabled=false

# Option 2: Deploy with webhooks + cert-manager
# First install cert-manager:
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s

# Then deploy the operator:
helm install node-maintenance-operator ./node-maintenance-operator \
  --namespace node-maintenance-operator-system \
  --create-namespace \
  --set webhook.enabled=true \
  --set webhook.certManager.enabled=true

# Or run the comprehensive test suite
./test-deployment.sh --namespace nmo-test --release-name test-nmo
```

### ⚠️ Important: Webhook Certificates

If you enable webhooks (`webhook.enabled=true`), you **must** provide TLS certificates. You have three options:

1. **Disable webhooks** (simplest for testing): `--set webhook.enabled=false`
2. **Use cert-manager** (recommended): Install cert-manager first, then enable `webhook.certManager.enabled=true`
3. **Manual certificates**: Create the secret `node-maintenance-operator-webhook-server-cert` manually

See the [Helm Deployment Guide](helm-deployment-guide.md) for detailed webhook configuration instructions.

### What's Next

1. **Deploy the Operator**: Use the Helm deployment guide above
2. **Test Functionality**: Create NodeMaintenance resources to test node cordoning/draining
3. **Monitor Operations**: Check logs and status of maintenance operations
4. **Explore Configuration**: Try different webhook, monitoring, and security settings 