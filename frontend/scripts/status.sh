#!/bin/bash

NAMESPACE="app"

echo "======================================"
echo "📊 Frontend Status"
echo "Namespace: $NAMESPACE"
echo "======================================"

echo
echo "📦 Pods:"
kubectl get pods \
  -n "$NAMESPACE" \
  -l app=frontend-app \
  -o wide

echo
echo "🌐 Services:"
kubectl get svc -n "$NAMESPACE"

echo
echo "🚀 Deployments:"
kubectl get deployment \
  -n "$NAMESPACE" \
  -l app=frontend-app

echo
echo "🌐 HTTPRoutes:"
kubectl get httproute \
  -n "$NAMESPACE" 2>/dev/null || echo "No HTTPRoute found"

echo
echo "⚙️ ConfigMaps:"
kubectl get configmap -n "$NAMESPACE"

echo
echo "======================================"