# cluster-setup.sh
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

# Create k3d cluster optimized for local development
echo "📦 Creating k3d cluster..."
k3d cluster create mx-trades \
    --servers 1 \
    --agents 1 \
    --port "8080:80@loadbalancer" \
    --port "8443:443@loadbalancer" \
    --port "9090:9090@loadbalancer" \
    --port "5601:5601@loadbalancer" \
    --api-port 6550 \
    --k3s-arg "--disable=traefik@server:0" \
    --servers-memory "2g" \
    --agents-memory "4g" \
    --registry-create mx-trades-registry:0.0.0.0:5555 \
    --timeout 5m

# Explicitly switch context
echo "🔄 Switching kubectl context to k3d-mx-trades..."
kubectl config use-context k3d-mx-trades

# Wait for cluster to be ready
echo "⏳ Waiting for cluster to be ready..."
until kubectl get nodes | grep -q "Ready"; do
    echo "Waiting for nodes to be ready..."
    sleep 5
done

# Create namespaces
echo "🏗️ Creating namespaces..."
kubectl create namespace monitoring
kubectl create namespace istio-system
kubectl create namespace logging
kubectl create namespace violations-module

# Label namespaces for Istio injection
kubectl label namespace violations-module istio-injection=enabled

# Add Helm repositories
echo "📚 Adding Helm repositories..."
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add elastic https://helm.elastic.co
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install Istio (minimal profile for local development)
echo "🕸️ Installing Istio..."
helm install istio-base istio/base \
    --namespace istio-system \
    --wait --timeout=300s

helm install istiod istio/istiod \
    --namespace istio-system \
    --set pilot.resources.requests.cpu=100m \
    --set pilot.resources.requests.memory=128Mi \
    --set pilot.resources.limits.cpu=200m \
    --set pilot.resources.limits.memory=256Mi \
    --set global.proxy.resources.requests.cpu=10m \
    --set global.proxy.resources.requests.memory=32Mi \
    --wait --timeout=300s

echo "📝 Installing Elasticsearch..."
helm install elasticsearch elastic/elasticsearch \
    --namespace logging \
    --set replicas=1 \
    --set minimumMasterNodes=1 \
    --set persistence.enabled=false \
    --wait --timeout=600s

# Install Kibana with stable configuration
echo "📊 Installing Kibana..."
helm install kibana-bkp elastic/kibana \
    --namespace logging \
    --version 7.17.3 \
    --set resources.requests.cpu=100m \
    --set resources.requests.memory=256Mi \
    --set resources.limits.memory=512Mi \
    --wait --timeout=300s

# Install Prometheus stack (minimal config for local dev)
echo "📊 Installing Prometheus and Grafana..."
helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set prometheus.prometheusSpec.resources.requests.cpu=100m \
    --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
    --set prometheus.prometheusSpec.resources.limits.memory=512Mi \
    --set grafana.resources.requests.cpu=100m \
    --set grafana.resources.requests.memory=128Mi \
    --set grafana.adminPassword=admin \
    --set grafana.service.type=ClusterIP \
    --set prometheus.service.type=ClusterIP \

# Install Kafka (single node for local development)
echo "📫 Installing Kafka..."
helm install kafka bitnami/kafka \
    --namespace violations-module \
    --set replicaCount=1 \
    --set heapOpts="-Xmx512m -Xms512m" \
    --set resources.requests.memory=512Mi \
    --set resources.limits.memory=1Gi \
    --set zookeeper.heapSize=256 \

# Install Redis (single node)
echo "📦 Installing Redis..."
helm install redis bitnami/redis \
    --namespace violations-module \
    --set architecture=standalone \
    --set auth.enabled=true \
    --set auth.password=development-password \
    --set master.resources.requests.cpu=100m \
    --set master.resources.requests.memory=128Mi \

# Install MariaDB (single node)
echo "💾 Installing MariaDB..."
helm install mariadb bitnami/mariadb \
    --namespace violations-module \
    --set architecture=standalone \
    --set auth.rootPassword=development-password \
    --set auth.database=violations \
    --set primary.resources.requests.cpu=100m \
    --set primary.resources.requests.memory=256Mi \

echo "✅ Cluster setup complete!"

echo """
🎉 Development cluster is ready! Quick access guide:

📊 Access services locally:
- Grafana: kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
  http://localhost:3000 (admin/admin)
  
- Kibana: kubectl port-forward svc/kibana-kibana 5601 -n logging
  http://localhost:5601
  
- Prometheus: kubectl port-forward svc/prometheus-prometheus 9090:9090 -n monitoring
  http://localhost:9090

- Kafka: kubectl port-forward svc/kafka 9092:9092 -n violations-module
  localhost:9092

- MariaDB: kubectl port-forward svc/mariadb 3306:3306 -n violations-module
  localhost:3306 (root/development-password)

🔍 Quick Commands:
- View all pods: kubectl get pods -A
- View services: kubectl get svc -A
- Get logs: kubectl logs -n <namespace> <pod-name>
- Shell into pod: kubectl exec -it -n <namespace> <pod-name> -- /bin/bash

💡 Development Tips:
- Use 'kubectl port-forward' to access services locally
- Check logs with 'kubectl logs' for troubleshooting
- Use 'k9s' for easier cluster navigation
- Local registry available at localhost:5000

📝 Common Issues:
- If pods are pending, check resources with: kubectl describe pod <pod-name>
- For OOM issues, view nodes status: kubectl describe nodes
"""