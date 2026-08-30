#!/bin/bash

set -e

NAMESPACE="app"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "======================================"
echo "🗑️ OMS Frontend Delete"
echo "======================================"

echo
echo "🌐 Deleting HTTPRoute..."
kubectl delete -f "$BASE_DIR/httproute.yml" \
  --ignore-not-found

echo
echo "🚀 Deleting Frontend Application..."
kubectl delete -f "$BASE_DIR/app.yml" \
  --ignore-not-found

echo
echo "⚙️ Deleting ConfigMap..."
kubectl delete -f "$BASE_DIR/configmap.yml" \
  --ignore-not-found

echo
echo "======================================"
echo "✅ Frontend resources deleted"
echo "======================================"

echo
echo "📦 Remaining Frontend Pods:"
kubectl get pods -n "$NAMESPACE" -l app=frontend-app 2>/dev/null || true

echo
echo "🌐 Remaining HTTPRoutes:"
kubectl get httproute -n "$NAMESPACE" 2>/dev/null || true