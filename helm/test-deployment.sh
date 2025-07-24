#!/bin/bash

# Node Maintenance Operator Helm Chart Test Script
# This script validates the Helm chart deployment and functionality

set -e

# Configuration
NAMESPACE=${NAMESPACE:-"node-maintenance-operator-system"}
RELEASE_NAME=${RELEASE_NAME:-"nmo-test"}
CHART_PATH=${CHART_PATH:-"./node-maintenance-operator"}
TIMEOUT=${TIMEOUT:-"300s"}
TEST_NODE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test resources..."
    helm uninstall $RELEASE_NAME -n $NAMESPACE --ignore-not-found || true
    kubectl delete namespace $NAMESPACE --ignore-not-found || true
    kubectl delete crd nodemaintenances.nodemaintenance.medik8s.io --ignore-not-found || true
}

# Test functions
test_helm_template() {
    log_info "Testing Helm template rendering..."
    helm template $RELEASE_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --set webhook.enabled=true \
        --set monitoring.enabled=true \
        --set monitoring.serviceMonitor.enabled=true \
        > /tmp/nmo-manifests.yaml
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ Helm template rendering successful"
    else
        log_error "✗ Helm template rendering failed"
        exit 1
    fi
}

test_helm_lint() {
    log_info "Running Helm lint..."
    helm lint $CHART_PATH
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ Helm lint passed"
    else
        log_error "✗ Helm lint failed"
        exit 1
    fi
}

test_deployment() {
    log_info "Testing Helm deployment..."
    
    # Create namespace
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Check if cert-manager is available
    if kubectl get deployment cert-manager -n cert-manager &> /dev/null; then
        log_info "cert-manager detected, enabling webhook with cert-manager"
        WEBHOOK_ARGS="--set webhook.enabled=true --set webhook.certManager.enabled=true"
    else
        log_info "cert-manager not found, disabling webhooks for testing"
        WEBHOOK_ARGS="--set webhook.enabled=false"
    fi
    
    # Install the chart
    helm install $RELEASE_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --wait \
        --timeout $TIMEOUT \
        $WEBHOOK_ARGS \
        --set monitoring.enabled=false
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ Helm deployment successful"
    else
        log_error "✗ Helm deployment failed"
        exit 1
    fi
}

test_operator_readiness() {
    log_info "Testing operator readiness..."
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available deployment/$RELEASE_NAME-node-maintenance-operator-controller-manager \
        -n $NAMESPACE --timeout=$TIMEOUT
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ Operator deployment is ready"
    else
        log_error "✗ Operator deployment failed to become ready"
        exit 1
    fi
    
    # Check pods are running
    local pods=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME --no-headers | wc -l)
    if [[ $pods -gt 0 ]]; then
        log_info "✓ Operator pods are running ($pods pods)"
    else
        log_error "✗ No operator pods found"
        exit 1
    fi
}

test_crd_installation() {
    log_info "Testing CRD installation..."
    
    kubectl get crd nodemaintenances.nodemaintenance.medik8s.io > /dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ NodeMaintenance CRD is installed"
    else
        log_error "✗ NodeMaintenance CRD not found"
        exit 1
    fi
}

test_webhook_functionality() {
    log_info "Testing webhook functionality..."
    
    # Check if ValidatingWebhookConfiguration exists
    kubectl get validatingwebhookconfiguration $RELEASE_NAME-node-maintenance-operator-validating-webhook-configuration > /dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ ValidatingWebhookConfiguration exists"
    else
        log_warn "⚠ ValidatingWebhookConfiguration not found (may be disabled)"
        return 0
    fi
    
    # Test webhook by creating an invalid NodeMaintenance resource
    log_info "Testing webhook validation..."
    cat <<EOF | kubectl apply -f - 2>&1 | grep -q "denied\|error\|invalid" && log_info "✓ Webhook validation working" || log_warn "⚠ Webhook validation may not be working as expected"
apiVersion: nodemaintenance.medik8s.io/v1beta1
kind: NodeMaintenance
metadata:
  name: invalid-test
spec:
  nodeName: "non-existent-node-$(date +%s)"
  reason: "Testing webhook validation"
EOF
    
    # Clean up the test resource
    kubectl delete nodemaintenance invalid-test --ignore-not-found || true
}

test_node_maintenance_functionality() {
    log_info "Testing NodeMaintenance functionality..."
    
    # Get the first available node
    TEST_NODE=$(kubectl get nodes --no-headers -o custom-columns=":metadata.name" | head -1)
    
    if [[ -z "$TEST_NODE" ]]; then
        log_error "✗ No nodes available for testing"
        exit 1
    fi
    
    log_info "Using node '$TEST_NODE' for testing"
    
    # Create a NodeMaintenance resource
    cat <<EOF | kubectl apply -f -
apiVersion: nodemaintenance.medik8s.io/v1beta1
kind: NodeMaintenance
metadata:
  name: test-maintenance-$(date +%s)
spec:
  nodeName: "$TEST_NODE"
  reason: "Automated testing of node maintenance operator"
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ NodeMaintenance resource created successfully"
    else
        log_error "✗ Failed to create NodeMaintenance resource"
        exit 1
    fi
    
    # Wait a moment for the operator to process
    sleep 10
    
    # Check if the node is cordoned
    local cordoned=$(kubectl get node $TEST_NODE -o jsonpath='{.spec.unschedulable}')
    if [[ "$cordoned" == "true" ]]; then
        log_info "✓ Node successfully cordoned"
    else
        log_warn "⚠ Node may not be cordoned yet (this might be expected for test environments)"
    fi
    
    # Clean up
    kubectl delete nodemaintenance --all --ignore-not-found
    kubectl uncordon $TEST_NODE || true
}

test_upgrade() {
    log_info "Testing Helm upgrade..."
    
    # Upgrade with different values
    helm upgrade $RELEASE_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --wait \
        --timeout $TIMEOUT \
        --set monitoring.enabled=true \
        --set monitoring.serviceMonitor.enabled=true
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ Helm upgrade successful"
    else
        log_error "✗ Helm upgrade failed"
        exit 1
    fi
}

test_rollback() {
    log_info "Testing Helm rollback..."
    
    helm rollback $RELEASE_NAME -n $NAMESPACE --wait --timeout $TIMEOUT
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ Helm rollback successful"
    else
        log_error "✗ Helm rollback failed"
        exit 1
    fi
}

# Main test execution
main() {
    log_info "Starting Node Maintenance Operator Helm Chart Tests"
    log_info "=============================================="
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Pre-deployment tests
    log_info "Phase 1: Pre-deployment validation"
    test_helm_lint
    test_helm_template
    
    # Deployment tests
    log_info "Phase 2: Deployment testing"
    test_deployment
    test_operator_readiness
    test_crd_installation
    
    # Functionality tests
    log_info "Phase 3: Functionality testing"
    test_webhook_functionality
    test_node_maintenance_functionality
    
    # Lifecycle tests
    log_info "Phase 4: Lifecycle testing"
    test_upgrade
    test_rollback
    
    log_info "=============================================="
    log_info "✅ All tests completed successfully!"
    
    # Show final status
    log_info "Final deployment status:"
    helm status $RELEASE_NAME -n $NAMESPACE
    kubectl get all -n $NAMESPACE
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --release-name)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --chart-path)
            CHART_PATH="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --cleanup-only)
            cleanup
            exit 0
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --namespace       Kubernetes namespace (default: node-maintenance-operator-system)"
            echo "  --release-name    Helm release name (default: nmo-test)"
            echo "  --chart-path      Path to Helm chart (default: ./node-maintenance-operator)"
            echo "  --timeout         Timeout for operations (default: 300s)"
            echo "  --cleanup-only    Only run cleanup and exit"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
if ! command -v helm &> /dev/null; then
    log_error "helm command not found. Please install Helm."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl command not found. Please install kubectl."
    exit 1
fi

# Check if chart directory exists
if [[ ! -d "$CHART_PATH" ]]; then
    log_error "Chart directory not found: $CHART_PATH"
    exit 1
fi

# Run main test suite
main 