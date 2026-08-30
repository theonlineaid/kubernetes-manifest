#!/bin/bash

set -e

cd "$(dirname "$0")/.."

NAMESPACE="app"

echo "======================================"
echo "🚀 Deploying Backend"
echo "Namespace: $NAMESPACE"
echo "======================================"

kubectl apply -f namespace.yml

kubectl apply -f secrate.yml -n "$NAMESPACE"
kubectl apply -f configmap.yml -n "$NAMESPACE"
kubectl apply -f postgres.yml -n "$NAMESPACE"
kubectl apply -f pgadmin.yml -n "$NAMESPACE"
kubectl apply -f seed.yml -n "$NAMESPACE"
kubectl apply -f app.yml -n "$NAMESPACE"

echo ""
echo "======================================"
echo "✅ Deployment completed"
echo "======================================"

kubectl get pods -n "$NAMESPACE"
kubectl get svc -n "$NAMESPACE"