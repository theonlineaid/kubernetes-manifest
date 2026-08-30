#!/bin/bash

set -e

NAMESPACE="app"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "======================================"
echo "🚀 OMS Frontend Deployment"
echo "======================================"

echo
echo "📦 Creating namespace..."
kubectl apply -f "$BASE_DIR/app.yml"

echo
echo "⚙️ Applying ConfigMap..."
kubectl apply -f "$BASE_DIR/configmap.yml"

echo
echo "🚀 Deploying Frontend Application..."
kubectl apply -f "$BASE_DIR/app.yml"

echo
echo "🌐 Applying HTTPRoute..."
kubectl apply -f "$BASE_DIR/httproute.yml"

echo
echo "⏳ Waiting for Frontend deployment..."

kubectl rollout status deployment/frontend-app \
  -n "$NAMESPACE" \
  --timeout=180s

echo
echo "======================================"
echo "✅ Frontend deployment completed!"
echo "======================================"

echo
echo "📦 Pods:"
kubectl get pods -n "$NAMESPACE" -l app=frontend-app -o wide

echo
echo "🌐 Services:"
kubectl get svc -n "$NAMESPACE"

echo
echo "🚀 Deployment:"
kubectl get deployment -n "$NAMESPACE"

echo
echo "🌐 HTTPRoute:"
kubectl get httproute -n "$NAMESPACE" 2>/dev/null || true

echo
echo "======================================"
echo "🎉 OMS Frontend deployment finished"
echo "======================================"