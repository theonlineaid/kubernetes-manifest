#!/bin/bash

cd "$(dirname "$0")/.."

NAMESPACE="app"

echo "======================================"
echo "📊 Backend Status"
echo "Namespace: $NAMESPACE"
echo "======================================"

echo ""
echo "📦 Pods:"
kubectl get pods -n "$NAMESPACE" -o wide

echo ""
echo "🌐 Services:"
kubectl get svc -n "$NAMESPACE"

echo ""
echo "🚀 Deployments:"
kubectl get deployments -n "$NAMESPACE"

echo ""
echo "🗄️ StatefulSets:"
kubectl get statefulsets -n "$NAMESPACE"

echo ""
echo "💾 PVC:"
kubectl get pvc -n "$NAMESPACE"

echo ""
echo "🔐 Secrets:"
kubectl get secrets -n "$NAMESPACE"

echo ""
echo "⚙️ ConfigMaps:"
kubectl get configmaps -n "$NAMESPACE"

echo ""
echo "======================================"