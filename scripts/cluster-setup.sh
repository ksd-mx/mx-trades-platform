#!/bin/bash

set -e

echo "🚀 Setting up local Kubernetes cluster for Traffic Brain..."

# Check prerequisites
command -v k3d >/dev/null 2>&1 || { echo "❌ k3d is required but not installed. Aborting." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed. Aborting." >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ helm is required but not installed. Aborting." >&2; exit 1; }

# Clean up any existing cluster
echo "🧹 Cleaning up any existing cluster..."
k3d cluster delete mx-trades 2>/dev/null || true

# Create k3d cluster
echo "📦 Creating k3d cluster..."
k3d cluster create mx-trades \
    --servers 1 \
    --agents 1 \
    --port "8080:80@loadbalancer" \
    --port "8443:443@loadbalancer" \
    --api-port 6550 

# Explicitly switch context
echo "🔄 Switching kubectl context to k3d-mx-trades..."
kubectl config use-context k3d-mx-trades

# Wait for cluster to be ready
echo "⏳ Waiting for cluster to be ready..."
sleep 30

# Verify cluster is ready
until kubectl get nodes | grep -q "Ready"; do
    echo "Waiting for nodes to be ready..."
    sleep 5
done
