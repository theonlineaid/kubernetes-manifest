#!/bin/bash

set -e

cd "$(dirname "$0")/.."

NAMESPACE="monitoring"
RELEASE="monitoring"
SECRET_NAME="grafana-admin"

echo ""
echo "======================================"
echo "🚀 OMS Monitoring Deployment (Prometheus + Grafana)"
echo "======================================"

# ------------------------------------------
# 1. Install Local Path Provisioner (skip if a default StorageClass exists)
# ------------------------------------------

if kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' | grep -q .; then
  echo ""
  echo "💾 Default StorageClass already present, skipping provisioner install."
else
  echo ""
  echo "💾 Installing Local Path Provisioner..."

  kubectl apply -f \
    https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

  echo ""
  echo "⏳ Waiting for Local Path Provisioner..."

  kubectl rollout status deployment/local-path-provisioner \
    -n local-path-storage \
    --timeout=120s

  kubectl patch storageclass local-path \
    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
fi

# ------------------------------------------
# 2. Create monitoring Namespace
# ------------------------------------------

echo ""
echo "📦 Creating namespace..."

kubectl apply -f namespace.yml

# ------------------------------------------
# 3. Grafana admin Secret (generate one if it doesn't exist yet)
# ------------------------------------------

echo ""
echo "🔐 Checking Grafana admin secret..."

if kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  echo "   Secret '$SECRET_NAME' already exists, leaving it as-is."
else
  GRAFANA_PASSWORD="$(openssl rand -base64 18)"

  kubectl create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$GRAFANA_PASSWORD"

  echo ""
  echo "   ✅ Created secret '$SECRET_NAME' — SAVE THESE, shown only once:"
  echo "      user:     admin"
  echo "      password: $GRAFANA_PASSWORD"
fi

# ------------------------------------------
# 4. Deploy kube-prometheus-stack via Helm
# ------------------------------------------

echo ""
echo "📡 Adding prometheus-community Helm repo..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update prometheus-community >/dev/null

echo ""
echo "📈 Installing/upgrading kube-prometheus-stack..."

helm upgrade --install "$RELEASE" prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  -f values.yaml \
  --wait --timeout 10m

# ------------------------------------------
# 5. Deployment Summary
# ------------------------------------------

echo ""
echo "======================================"
echo "✅ Monitoring deployment completed!"
echo "======================================"

echo ""
echo "📦 Pods (expect node-exporter once per node, master included):"
kubectl get pods -n "$NAMESPACE" -o wide

echo ""
echo "🌐 Services:"
kubectl get svc -n "$NAMESPACE"

echo ""
echo "🩺 node-exporter DaemonSet coverage:"
kubectl -n "$NAMESPACE" get daemonset -l app.kubernetes.io/name=prometheus-node-exporter \
  -o custom-columns=NAME:.metadata.name,DESIRED:.status.desiredNumberScheduled,READY:.status.numberReady

echo ""
echo "🌐 Grafana → http://<any-node-ip>:30300"
echo "======================================"
