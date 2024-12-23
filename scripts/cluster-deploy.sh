# Setup storage class
echo "💾 Setting up storage..."
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF

# Add Helm repositories
echo "📚 Adding Helm repositories..."
helm repo add jetstack https://charts.jetstack.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

# Create namespaces
echo "🏗️ Creating namespaces..."
kubectl create namespace monitoring
kubectl create namespace cert-manager
kubectl create namespace istio-system

# Install Istio with health checks
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
    --wait --timeout=300s

# Install Prometheus stack with verified settings
echo "📊 Installing Prometheus and Grafana..."
helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set grafana.adminPassword=admin \
    --set grafana.service.type=LoadBalancer \
    --set prometheus.service.type=LoadBalancer \
    --set admissionWebhooks.patch.image.repository=docker.io/jettech/kube-webhook-certgen \
    --set admissionWebhooks.patch.image.tag=v1.5.1

# Create Traefik IngressRoute for Grafana
echo "🔌 Creating IngressRoute for Grafana..."
kubectl apply -f - <<EOF
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  entryPoints:
    - web
  routes:
    - match: PathPrefix(\`/grafana\`)
      kind: Rule
      services:
        - name: prometheus-grafana
          port: 80
EOF

echo "✅ Cluster setup complete!"
echo "🔍 Checking pod status..."
kubectl get pods -A

echo """
🎉 Setup completed! Here's how to access your services:

📊 Grafana: http://localhost:8080/grafana
   Username: admin
   Password: admin

To access Traefik dashboard:
kubectl port-forward -n kube-system \$(kubectl get pods -n kube-system | grep '^traefik-' | awk '{print \$1}') 9000:9000
Then visit: http://localhost:9000/dashboard/

To verify persistent volumes:
kubectl get pv,pvc -A

To check pod status:
kubectl get pods -A

To check services:
kubectl get svc -A
"""
