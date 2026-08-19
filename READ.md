# 1. Namespace
kubectl apply -f namespace.yaml

# 2. Secret (git-এ যাবে না, সরাসরি cluster-এ বানান)
kubectl create secret generic backend-secret \
  --namespace backend \
  --from-literal=POSTGRES_USER=appuser \
  --from-literal=POSTGRES_PASSWORD='YOUR_STRONG_PASSWORD' \
  --from-literal=PGADMIN_DEFAULT_PASSWORD='YOUR_STRONG_PASSWORD'

# 3. Config
kubectl apply -f configmap.yaml

# 4. Postgres
kubectl apply -f postgres.yaml
kubectl -n backend rollout status deployment/postgres

# 5. Seed data
kubectl apply -f seed-job.yaml
kubectl -n backend logs job/backend-seed -f

# 6. App
kubectl apply -f app.yaml

# 7. pgAdmin
kubectl apply -f pgadmin.yaml

# 8. Verify
kubectl -n app get pods,svc,job



# 1. Storage provisioner ইনস্টল করুন
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

# 2. যাচাই করুন
kubectl get storageclass

# 3. Default বানান
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 4. Postgres + pgAdmin আবার apply
kubectl apply -f postgres.yaml
kubectl apply -f pgadmin.yaml
kubectl -n app get pvc

# 5. Postgres রেডি হওয়া পর্যন্ত অপেক্ষা
kubectl -n app rollout status deployment/postgres

# 6. Seed job রিসেট
kubectl -n app delete job seed
kubectl apply -f seed-job.yaml
kubectl -n app logs job/seed -f

# 7. App রিডিপ্লয় (port fix সহ)
kubectl apply -app.yaml
kubectl -n app rollout restart deployment/backend-app

# 8. চূড়ান্ত চেক
kubectl -n app get pods,svc,pvc,job