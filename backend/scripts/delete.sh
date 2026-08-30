#!/bin/bash

set -e

cd "$(dirname "$0")/.."

NAMESPACE="app"

echo "======================================"
echo "🗑️ Deleting Backend"
echo "Namespace: $NAMESPACE"
echo "======================================"

kubectl delete namespace "$NAMESPACE" --ignore-not-found

echo ""
echo "======================================"
echo "✅ Namespace '$NAMESPACE' deleted"
echo "======================================"