# Deploy order (backend + frontend, namespace: app)

Run these in order from the `infra/` directory. Every manifest lives under
`backend/` or `frontend/` and targets the `app` namespace.

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
kubectl -n argocd port-forward svc/argocd-server 8080:443
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
kubectl -n argocd port-forward svc/argocd-server 8080:443
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

## Troubleshooting