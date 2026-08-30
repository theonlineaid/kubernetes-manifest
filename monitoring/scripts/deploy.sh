#!/bin/bash

set -e

cd "$(dirname "$0")/.."

NAMESPACE="monitoring"
SECRET_NAME="grafana-admin"
ARGOCD_NAMESPACE="argocd"
ARGOCD_APP_FILE="../argocd/monitoring-app.yml"
ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

echo ""
echo "======================================"
echo "🚀 OMS Monitoring Deployment (Prometheus + Grafana via ArgoCD)"
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
# 4. Install ArgoCD control plane (skip if already present)
# ------------------------------------------

echo ""
echo "🔎 Checking for ArgoCD..."

if kubectl -n "$ARGOCD_NAMESPACE" get deployment argocd-server >/dev/null 2>&1; then
  echo "   ArgoCD already installed, skipping."
else
  echo "   Not found — installing ArgoCD control plane..."

  kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n "$ARGOCD_NAMESPACE" -f "$ARGOCD_INSTALL_URL"

  echo ""
  echo "⏳ Waiting for argocd-server..."
  kubectl -n "$ARGOCD_NAMESPACE" rollout status deployment/argocd-server --timeout=300s
fi

# ------------------------------------------
# 5. Apply the monitoring Application (ArgoCD renders the Helm chart itself,
#    no local `helm` binary needed; syncPolicy.automated does the rest)
# ------------------------------------------

echo ""
echo "📡 Applying ArgoCD Application (kube-prometheus-stack)..."

kubectl apply -f "$ARGOCD_APP_FILE"

echo ""
echo "⏳ Waiting for ArgoCD to sync (first sync pulls the chart + CRDs, can take a few minutes)..."

for _ in $(seq 1 60); do
  SYNC="$(kubectl -n "$ARGOCD_NAMESPACE" get application monitoring -o jsonpath='{.status.sync.status}' 2>/dev/null)"
  HEALTH="$(kubectl -n "$ARGOCD_NAMESPACE" get application monitoring -o jsonpath='{.status.health.status}' 2>/dev/null)"
  if [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
    echo "   Synced=$SYNC Health=$HEALTH"
    break
  fi
  echo "   Synced=${SYNC:-Unknown} Health=${HEALTH:-Unknown}, waiting..."
  sleep 5
done

# ------------------------------------------
# 6. Deployment Summary
# ------------------------------------------

echo ""
echo "======================================"
echo "✅ Monitoring deployment completed!"
echo "======================================"

echo ""
echo "🔧 ArgoCD Application:"
kubectl -n "$ARGOCD_NAMESPACE" get application monitoring

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
