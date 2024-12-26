#!/bin/bash
# File: platform/scripts/test-service-deploy.sh

set -e

# Configuration
SERVICE_NAME="test-service"
NAMESPACE="violations-module"
LOCAL_REGISTRY="localhost:5555"      # For local docker push
K8S_REGISTRY="mx-trades-registry:5555"  # For k8s to pull

# Build the Docker image
echo "🏗️ Building Docker image for ${SERVICE_NAME}..."
docker build -t ${SERVICE_NAME}:latest ../services/${SERVICE_NAME}

# Tag and push to local registry
echo "📦 Pushing image to registry..."
docker tag ${SERVICE_NAME}:latest ${LOCAL_REGISTRY}/${SERVICE_NAME}:latest
docker push ${LOCAL_REGISTRY}/${SERVICE_NAME}:latest

# Deploy using Helm
echo "🚀 Deploying ${SERVICE_NAME} to Kubernetes..."
helm upgrade --install ${SERVICE_NAME} \
    ./helm/charts/${SERVICE_NAME} \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --set image.repository=${K8S_REGISTRY}/${SERVICE_NAME} \
    --set image.tag=latest \
    --wait

# Verify deployment
echo "🔍 Verifying deployment..."
kubectl wait --for=condition=available deployment/${SERVICE_NAME} \
    --namespace ${NAMESPACE} \
    --timeout=120s || true  # Don't fail if timeout

# Show pod status
echo "📊 Pod Status:"
kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${SERVICE_NAME}
kubectl describe pod -n ${NAMESPACE} -l app.kubernetes.io/name=${SERVICE_NAME}

echo """
🎉 Deployment completed!

To test the service:
  kubectl port-forward svc/${SERVICE_NAME} 8000:8000 -n ${NAMESPACE}

Then visit:
  http://localhost:8000/hello    - Test the service
  http://localhost:8000/metrics  - View Prometheus metrics

To view logs:
  kubectl logs -f deployment/${SERVICE_NAME} -n ${NAMESPACE}
"""