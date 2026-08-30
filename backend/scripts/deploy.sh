#!/bin/bash

set -e

# ==========================================
# OMS Backend Kubernetes Deployment
# ==========================================

cd "$(dirname "$0")/.."

NAMESPACE="app"

echo ""
echo "======================================"
echo "🚀 OMS Backend Deployment"
echo "======================================"

# ------------------------------------------
# 1. Install Local Path Provisioner
# ------------------------------------------

echo ""
echo "💾 Installing Local Path Provisioner..."

kubectl apply -f \
  https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

echo ""
echo "⏳ Waiting for Local Path Provisioner..."

kubectl rollout status deployment/local-path-provisioner \
  -n local-path-storage \
  --timeout=120s

# ------------------------------------------
# 2. Make local-path the default StorageClass
# ------------------------------------------

echo ""
echo "💾 Configuring local-path as default StorageClass..."

kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo ""
echo "StorageClass:"
kubectl get storageclass

# ------------------------------------------
# 3. Create Application Namespace
# ------------------------------------------

echo ""
echo "📦 Creating namespace..."

kubectl apply -f namespace.yml

# ------------------------------------------
# 4. Apply Secret
# ------------------------------------------

echo ""
echo "🔐 Applying Secret..."

kubectl apply -f secrate.yml

# ------------------------------------------
# 5. Apply ConfigMap
# ------------------------------------------

echo ""
echo "⚙️ Applying ConfigMap..."

kubectl apply -f configmap.yml

# ------------------------------------------
# 6. Deploy PostgreSQL
# ------------------------------------------

echo ""
echo "🐘 Deploying PostgreSQL..."

kubectl apply -f postgres.yml

# ------------------------------------------
# 7. Deploy PgAdmin
# ------------------------------------------

echo ""
echo "🖥️ Deploying PgAdmin..."

kubectl apply -f pgadmin.yml

# ------------------------------------------
# 8. Deploy Seed Job
# ------------------------------------------

echo ""
echo "🌱 Deploying Database Seed..."

kubectl apply -f seed.yml

# ------------------------------------------
# 9. Deploy Backend Application
# ------------------------------------------

echo ""
echo "🚀 Deploying Backend Application..."

kubectl apply -f app.yml

# ------------------------------------------
# 10. Deployment Summary
# ------------------------------------------

echo ""
echo "======================================"
echo "✅ Deployment completed!"
echo "======================================"

echo ""
echo "📦 Namespace:"
kubectl get namespace "$NAMESPACE"

echo ""
echo "💾 StorageClass:"
kubectl get storageclass

echo ""
echo "💾 PVC:"
kubectl get pvc -n "$NAMESPACE"

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
echo "======================================"
echo "🎉 OMS Backend deployment finished"
echo "======================================"