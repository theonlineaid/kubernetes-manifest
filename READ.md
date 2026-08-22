# Deploy order (backend + frontend, namespace: app)

Run these in order from the `infra/` directory. Every manifest lives under
`backend/` or `frontend/` and targets the `app` namespace. Monitoring
(§12) lives under `monitoring/` and targets its own `monitoring` namespace.

## 0. Storage provisioner (bare-metal / no default StorageClass only)

Skip this on a managed cluster (EKS/GKE/AKS) that already has a default
StorageClass — only needed when `kubectl get storageclass` shows nothing
marked `(default)`.

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
kubectl get storageclass
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## 1. Namespace

```bash
kubectl apply -f backend/namespace.yml
```

## 2. Secret (git-এ commit করবেন না — সরাসরি cluster-এ বানান)

`backend/secrate.yml` শুধু reference — আসল value cluster-এ imperatively বানান:

```bash
kubectl create secret generic backend-secret \
  --namespace app \
  --from-literal=POSTGRES_USER=appuser \
  --from-literal=POSTGRES_PASSWORD='YOUR_STRONG_PASSWORD' \
  --from-literal=PGADMIN_DEFAULT_PASSWORD='YOUR_STRONG_PASSWORD'
```

## 3. Backend config

```bash
kubectl apply -f backend/configmap.yml
```

## 4. Postgres — Postgres রেডি না হওয়া পর্যন্ত পরের ধাপে যাবেন না

```bash
kubectl apply -f backend/postgres.yml
kubectl -n app rollout status deployment/postgres
kubectl -n app get pvc
```

## 5. Seed job — টেবিল বানায় + sample data ঢোকায়

```bash
kubectl apply -f backend/seed.yml
kubectl -n app logs job/backend-seed -f
```

To re-run the seed job after editing it:

```bash
kubectl -n app delete job backend-seed
kubectl apply -f backend/seed.yml
kubectl -n app logs job/backend-seed -f
```

## 6. Backend app (Deployment + Service, port 5000, NodePort 30080)

```bash
kubectl apply -f backend/app.yml
kubectl -n app rollout status deployment/backend-app
```

## 7. pgAdmin (ঐচ্ছিক — DB দেখার জন্য, NodePort 30050)

```bash
kubectl apply -f backend/pgadmin.yml
```

## 8. Frontend config + app — সবশেষে, কারণ এর `API_URL=http://backend-app:5000`
কাজ করবে শুধু backend Service ততক্ষণে ready থাকলে (NodePort 30081)

```bash
kubectl apply -f frontend/configmap.yml
kubectl apply -f frontend/app.yml
kubectl -n app rollout status deployment/frontend-app
```

## 9. Verify everything

```bash
kubectl -n app get pods,svc,pvc,job
```

Then hit:

- Backend API → `http://<any-node-ip>:30080/health`
- pgAdmin → `http://<any-node-ip>:30050`
- Frontend → `http://<any-node-ip>:30081`

## 10. ArgoCD (GitOps — optional, replaces manual `kubectl apply` of steps 3–8)

One-time install of the ArgoCD control plane itself:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-server
```

Get the initial admin password and log in (via port-forward, or your LoadBalancer/Ingress if you have one):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8082:443
# then: argocd login localhost:8080 --username admin
```

Then point ArgoCD at this same repo (`kubernetes-manifest`) — one `apply` and
it creates + syncs both `backend-app` and `frontend-app` for you:

```bash
kubectl apply -f argocd/root-app.yml
kubectl -n argocd get applications
```

(Or apply `argocd/backend-app.yml` and `argocd/frontend-app.yml` directly if
you don't want the app-of-apps wrapper.)

**Still do manually, outside GitOps:**
- Step 0 (storage provisioner) — cluster-level, one-time, not app config.
- Step 2 (the `backend-secret`) — real credentials never go in git.
  `backend-app.yml`'s Application excludes `secrate.yml` from sync for this
  reason; create the secret yourself before the first sync.

**Known limitation with `:latest` tags:** both `app.yml` files pull
`onlineaid/*-app:latest` with `imagePullPolicy: Always`. Since the manifest
text never changes when CI pushes a new `:latest` image, ArgoCD sees "no
diff" and won't redeploy automatically — you'd still need
`kubectl rollout restart deployment/<name>` after each image push (or run
[Argo CD Image Updater](https://argocd-image-updater.readthedocs.io/), or
have CI commit a `:sha-xxxxxxx` tag into the manifest instead of `:latest`,
which is the more correct GitOps pattern).

## 11. Gateway API + custom domain (optional)

Right now frontend/backend/pgAdmin are only reachable via NodePort on the
node's IP (`30081`/`30080`/`30050`). To put a real domain in front of the
frontend and backend with clean URLs (no port number):

**Note:** the community `kubernetes/ingress-nginx` project was retired in
March 2026 (archived, no more security patches), so this uses the
[Gateway API](https://gateway-api.sigs.k8s.io/) — the direction Kubernetes
SIG Network now recommends — with [Envoy Gateway](https://gateway.envoyproxy.io/)
as the controller.

### a. Install the Gateway API CRDs + Envoy Gateway controller (one-time)

No Helm needed — this single static manifest bundles both the Gateway API
CRDs and the Envoy Gateway controller, and installs into the
`envoy-gateway-system` namespace:

```bash
kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.9.0/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/envoy-gateway -n envoy-gateway-system
```

### b. Point Envoy at the node's own IP (no spare IP / no MetalLB)

There's only one IP here (`40.40.40.51`) and no cloud LoadBalancer, so this
binds the Envoy proxy pod straight to the node's port 80 via `hostPort`
(`gateway/envoyproxy.yml`) — a working community pattern, not an officially
documented EnvoyProxy field. If you ever get a second, unused IP on the same
network, switch to [MetalLB](https://metallb.io/) instead — that's Envoy
Gateway's actual documented bare-metal path and doesn't need this patch.

```bash
kubectl apply -f gateway/envoyproxy.yml
kubectl apply -f gateway/gatewayclass.yml
kubectl apply -f gateway/gateway.yml
```

Verify the hostPort actually landed on the Envoy pod before moving on:

```bash
kubectl -n envoy-gateway-system get pods
kubectl -n envoy-gateway-system get pod -l gateway.envoyproxy.io/owning-gateway-name=eg -o jsonpath='{.items[0].spec.containers[0].ports}'
# expect to see "hostPort": 80 in there
```

### c. DNS

At your domain registrar, create A records pointing at your node's public IP:

| Type | Host                 | Value       |
|------|----------------------|-------------|
| A    | app.yourdomain.com   | 40.40.40.51 |
| A    | api.yourdomain.com   | 40.40.40.51 |

pgAdmin intentionally gets **no** DNS entry here — it's a full DB admin UI,
so keep it reachable only via the NodePort (`30050`) or `kubectl port-forward`,
not a public domain.

### d. HTTPRoutes

Edit the `hostnames:` field in `frontend/httproute.yml` and
`backend/httproute.yml` to your real domain, then:

```bash
kubectl apply -f frontend/httproute.yml
kubectl apply -f backend/httproute.yml
```

Verify:

```bash
curl http://app.yourdomain.com/
curl http://api.yourdomain.com/health
```

### e. HTTPS (optional but recommended)

`cert-manager` supports Gateway API natively (`Gateway` resources instead of
`Ingress`):

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl -n cert-manager rollout status deployment/cert-manager-webhook
```

Then create a `ClusterIssuer` for Let's Encrypt and add a `tls:` block plus
an HTTPS listener to `gateway/gateway.yml` — ask if you want this wired up too.

## 12. Monitoring — Prometheus + Grafana (optional)

Cluster-wide metrics via the community
[`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
Helm chart (Prometheus Operator, Prometheus, Alertmanager, Grafana,
node-exporter, kube-state-metrics — one chart, one multi-source ArgoCD
Application). Runs in its own `monitoring` namespace, separate from `app`.

```
monitoring/
├── namespace.yml   # the `monitoring` namespace (also auto-created by CreateNamespace=true)
└── values.yaml     # Helm values for the chart — tracked in git, diffable
argocd/
└── monitoring-app.yml   # Application: chart from the Helm repo, values from monitoring/values.yaml
```

`monitoring-app.yml` uses ArgoCD's multi-source Application feature: one
source is the `kube-prometheus-stack` chart from the prometheus-community
Helm repo, the other is this same git repo, referenced via `$values` so the
chart picks up `monitoring/values.yaml` — same idea as `backend/`/`frontend/`,
just for a Helm-based app instead of raw manifests.

### a. Grafana admin credentials — create before the first sync

Same rule as `backend-secret` (step 2): real credentials never go in git.
`monitoring/values.yaml` points Grafana at an `existingSecret` instead of a
plaintext password, so create it yourself first:

```bash
kubectl apply -f monitoring/namespace.yml
kubectl create secret generic grafana-admin \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='YOUR_STRONG_PASSWORD'
```

### b. Deploy

```bash
kubectl apply -f argocd/monitoring-app.yml
kubectl -n argocd get application monitoring
kubectl -n monitoring get pods
```

First sync pulls the Helm chart and its CRDs (`ServiceMonitor`,
`PodMonitor`, etc.) — this can take a couple of minutes on first apply.

### c. Access

- Grafana → `http://<any-node-ip>:30300` (NodePort, same pattern as pgAdmin
  — no public DNS entry, since this is an internal ops tool). Log in with
  the `grafana-admin` secret you created above. Dashboards for cluster/node/
  pod metrics ship enabled by default with the chart.
- Prometheus and Alertmanager are kept `ClusterIP`-only (not exposed via
  NodePort or the Gateway) — reach them when needed via port-forward:
  ```bash
  kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
  kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093
  ```

### d. Sizing note

This is tuned down for the single-node bare-metal box this repo targets
(low `resources.requests/limits`, 7-day Prometheus retention, 10Gi PVC for
Prometheus / 2Gi for Grafana via the default StorageClass — see step 0).
Raise `prometheus.prometheusSpec.retention` and the storage sizes in
`monitoring/values.yaml` if the node has room to spare.

**Known kubeadm caveat:** `kubeControllerManager` / `kubeScheduler` /
`kubeEtcd` targets in Prometheus may show as `down` if those static pods
bind their metrics port to `127.0.0.1` instead of `0.0.0.0` (common default
on kubeadm-provisioned clusters) — see the chart's
[README](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack#kube-scheduler)
for the manifest patch if you need those specific targets.

## Troubleshooting

- **`ImagePullBackOff`** — `backend/app.yml` and `frontend/app.yml` pull
  `onlineaid/backend-app:latest` / `onlineaid/frontend-app:latest`. Make sure
  that's the actual DockerHub username the CI/CD pipelines push to
  (`secrets.DOCKERHUB_USERNAME` in each repo's `.github/workflows/deploy.yml`).
- **`CreateContainerConfigError` on postgres** — the secret (step 2) wasn't
  created yet; `postgres.yml` reads `backend-secret` directly.
- **Frontend loads but API calls fail (`fetch failed`)** — the backend
  Deployment isn't ready yet, or its Service name changed. `API_URL` must
  match the backend Service's `metadata.name` (`backend-app`) exactly, since
  that's how in-cluster DNS resolves it.
- **After a redeploy with config/image changes**, restart the Deployment to
  pick them up:
  ```bash
  kubectl -n app rollout restart deployment/backend-app
  kubectl -n app rollout restart deployment/frontend-app
  ```
- **`curl` to your domain hangs or connection refused** — check
  `kubectl -n envoy-gateway-system get pods` are `Running`, then confirm the
  `hostPort` patch in `gateway/envoyproxy.yml` actually applied (see the
  verify command in §11b) — if it didn't, the Envoy pod is only reachable
  inside the cluster, not on the node's port 80.
- **`HTTPRoute` traffic 404s** — check
  `kubectl -n app get httproute frontend-app backend-app -o yaml` for a
  `status.parents[].conditions` of `Accepted: True` / `ResolvedRefs: True`,
  and that `hostnames:` in `frontend/httproute.yml` / `backend/httproute.yml`
  matches your DNS record exactly (typos here are the most common cause).