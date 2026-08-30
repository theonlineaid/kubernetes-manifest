#!/bin/bash

set -e

cd "$(dirname "$0")/.."

NAMESPACE="monitoring"
ARGOCD_NAMESPACE="argocd"
ARGOCD_APP_FILE="../argocd/monitoring-app.yml"

echo "======================================"
echo "🗑️  Deleting Monitoring"
echo "Namespace: $NAMESPACE"
echo "======================================"

echo ""
echo "⚠️  This removes Prometheus/Grafana/Alertmanager and their PVCs"
echo "   (local-path reclaim policy is Delete — data is gone, not just detached)."

echo ""
echo "📉 Deleting ArgoCD Application (cascades to the Helm-rendered resources)..."
kubectl delete -f "$ARGOCD_APP_FILE" --ignore-not-found -n "$ARGOCD_NAMESPACE"

echo ""
echo "📦 Deleting namespace (PVCs, secrets, any leftovers)..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found

echo ""
echo "======================================"
echo "✅ Namespace '$NAMESPACE' deleted"
echo "======================================"
