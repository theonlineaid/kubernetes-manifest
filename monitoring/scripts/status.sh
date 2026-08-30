#!/bin/bash

cd "$(dirname "$0")/.."

NAMESPACE="monitoring"
ARGOCD_NAMESPACE="argocd"

echo "======================================"
echo "📊 Monitoring Status"
echo "Namespace: $NAMESPACE"
echo "======================================"

echo ""
echo "🔧 ArgoCD Application:"
kubectl -n "$ARGOCD_NAMESPACE" get application monitoring 2>/dev/null || echo "   (not found — deployed without ArgoCD?)"

echo ""
echo "📦 Pods:"
kubectl get pods -n "$NAMESPACE" -o wide

echo ""
echo "🌐 Services:"
kubectl get svc -n "$NAMESPACE"

echo ""
echo "🩺 node-exporter DaemonSet coverage (want DESIRED == READY, one per node):"
kubectl -n "$NAMESPACE" get daemonset -l app.kubernetes.io/name=prometheus-node-exporter \
  -o custom-columns=NAME:.metadata.name,DESIRED:.status.desiredNumberScheduled,READY:.status.numberReady

echo ""
echo "💾 PVC:"
kubectl get pvc -n "$NAMESPACE"

echo ""
echo "======================================"
echo "🌍 Reachable at"
echo "======================================"

GRAFANA_PORT="$(kubectl -n "$NAMESPACE" get svc -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].spec.ports[?(@.name=="service")].nodePort}' 2>/dev/null)"

if [ -z "$GRAFANA_PORT" ]; then
  echo "⚠️  Grafana service not found (is the release deployed?)"
else
  echo ""
  echo "Grafana (NodePort $GRAFANA_PORT) — open any of these:"
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.addresses[?(@.type=="InternalIP")]}{.address}{end}{"\n"}{end}' \
    | while read -r node ip; do
        echo "  http://$ip:$GRAFANA_PORT   ($node)"
      done
fi

echo ""
echo "Prometheus / Alertmanager are ClusterIP-only, reach via port-forward:"
echo "  kubectl -n $NAMESPACE port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090"
echo "  kubectl -n $NAMESPACE port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093"

echo ""
echo "======================================"
