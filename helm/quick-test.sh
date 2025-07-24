#!/usr/bin/env bash
# -*- coding: UTF-8 -*-
echo "=== Node Maintenance Operator Test ==="

# Get test node
NODE_NAME=$(kubectl get nodes --no-headers -o custom-columns=":metadata.name" | head -1)
echo "Testing with node: $NODE_NAME"

# Create test NodeMaintenance
kubectl apply -f - <<EOF
apiVersion: nodemaintenance.medik8s.io/v1beta1
kind: NodeMaintenance
metadata:
  name: quick-test
spec:
  nodeName: $NODE_NAME
  reason: "Quick functionality test"
EOF

echo "Waiting for node to be cordoned..."
sleep 10

# Check if cordoned
CORDONED=$(kubectl get node $NODE_NAME -o jsonpath='{.spec.unschedulable}')
if [ "$CORDONED" = "true" ]; then
    echo "✅ SUCCESS: Node $NODE_NAME is cordoned"
else
    echo "❌ FAILED: Node $NODE_NAME is not cordoned"
fi

# Check NodeMaintenance status
PHASE=$(kubectl get nodemaintenance quick-test -o jsonpath='{.status.phase}')
echo "NodeMaintenance phase: $PHASE"

# Cleanup
kubectl delete nodemaintenance quick-test
echo "Test completed. Cleaned up NodeMaintenance resource."
