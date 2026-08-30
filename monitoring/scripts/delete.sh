#!/bin/bash

set -e

cd "$(dirname "$0")/.."

NAMESPACE="monitoring"
RELEASE="monitoring"

echo "======================================"
echo "🗑️  Deleting Monitoring"
echo "Namespace: $NAMESPACE"
echo "======================================"

echo ""
echo "⚠️  This removes Prometheus/Grafana/Alertmanager and their PVCs"
echo "   (local-path reclaim policy is Delete — data is gone, not just detached)."

echo ""
echo "📉 Uninstalling Helm release..."
helm uninstall "$RELEASE" -n "$NAMESPACE" 2>/dev/null || echo "   (release '$RELEASE' not found, skipping)"

echo ""
echo "📦 Deleting namespace (PVCs, secrets, CRDs' CRs included)..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found

echo ""
echo "======================================"
echo "✅ Namespace '$NAMESPACE' deleted"
echo "======================================"
