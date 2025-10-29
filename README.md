# Mattermost Deployment with Kubernetes

## Namespace & Ingress Controller

```bash
kubectl create namespace mattermost || true
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace mattermost --create-namespace
```
```bash
kubectl get pods --namespace=mattermost
```

## Install Mattermost Operator

```bash
helm repo add mattermost https://helm.mattermost.com
helm upgrade --install mattermost-operator mattermost/mattermost-operator -n mattermost -f config.yaml
```

## Deploy PostgreSQL (in-cluster)

```bash
kubectl apply -f postgres/postgres-configmap.yaml -n mattermost
kubectl apply -f postgres/postgres-pv.yaml -n mattermost
kubectl apply -f postgres/postgres-claim.yaml -n mattermost
kubectl apply -f postgres/postgres-deployment.yaml -n mattermost
kubectl apply -f postgres/postgres-service.yaml -n mattermost

## Deploy MinIO (in-cluster)

```bash
kubectl apply -f minio/minio-pv.yaml -n mattermost
kubectl apply -f minio/minio-pvc.yaml -n mattermost
kubectl apply -f minio/minio-deployment.yaml -n mattermost
kubectl apply -f minio/minio-service.yaml -n mattermost
```

Create the bucket used by Mattermost:

```bash
kubectl apply -f minio/minio-bucket-job.yaml -n mattermost
kubectl -n mattermost wait --for=condition=complete --timeout=120s job/minio-create-bucket || true
```

## Create Secrets

YAML-based (fill base64 values in files):

```bash
kubectl apply -f mattermost-filestore-secret.yaml -n mattermost
kubectl apply -f mattermost-database-secret.yaml -n mattermost
```

Or command-based (no YAML):

```bash
# Replace values accordingly
export MM_DB_USER=mattermost_user
export MM_DB_PASS=PassWDPG
export MM_DB_HOST=postgres
export MM_DB_NAME=mattermost
export MM_DB_PORT=5432

kubectl -n mattermost create secret generic mattermost-db-credentials \
  --from-literal=MM_SQLSETTINGS_DATASOURCE="postgres://${MM_DB_USER}:${MM_DB_PASS}@${MM_DB_HOST}:${MM_DB_PORT}/${MM_DB_NAME}?sslmode=disable" \
  --from-literal=DB_CONNECTION_CHECK_URL="postgres://${MM_DB_HOST}:${MM_DB_PORT}/${MM_DB_NAME}?sslmode=disable" --dry-run=client -o yaml | kubectl apply -f -

export MINIO_ACCESS_KEY=minioadmin
export MINIO_SECRET_KEY=minioadmin
kubectl -n mattermost create secret generic minio-credentials \
  --from-literal=accesskey="${MINIO_ACCESS_KEY}" \
  --from-literal=secretkey="${MINIO_SECRET_KEY}" --dry-run=client -o yaml | kubectl apply -f -
```

### How to base64-encode values for the YAML files

When using the YAML-based secrets, fields under `data:` must be base64-encoded.

- Encode any literal value:

```bash
echo -n 'plain-text-value' | base64
```

- Example: MinIO `accesskey` and `secretkey` for `mattermost-filestore-secret.yaml`:

```bash
echo -n "minioadmin" | base64   # use output for accesskey
echo -n "minioadmin" | base64   # use output for secretkey
```

- Example: Database DSN values for `mattermost-database-secret.yaml`:

```bash
DSN="postgres://mattermost_user:PassWDPG@postgres:5432/mattermost?sslmode=disable"
echo -n "$DSN" | base64   # use output for MM_SQLSETTINGS_DATASOURCE

CHECK_URL="postgres://postgres:5432/mattermost?sslmode=disable"
echo -n "$CHECK_URL" | base64   # use output for DB_CONNECTION_CHECK_URL
```

- Decode (to verify):

```bash
echo 'BASE64_STRING' | base64 --decode
```

## Deploy Mattermost Instance

```bash
kubectl apply -f mattermost-installation.yaml -n mattermost
kubectl get pods -n mattermost -w
```

Ingress host configured: `team.viduli.dev`. Point DNS to your ingress controller and, if needed, add TLS annotations/cert-manager config to the operator-managed Ingress.

## One-shot deploy (script)

If you prefer a single command that chains all steps above:

```bash
chmod +x ./deploy-all.sh
NAMESPACE=mattermost MM_HOST=team.viduli.dev \
MM_DB_USER=mattermost_user MM_DB_PASS=PassWDPG MM_DB_NAME=mattermost \
MINIO_ACCESS_KEY=minioadmin MINIO_SECRET_KEY=minioadmin \
./deploy-all.sh
```

## One-shot deploy (Makefile)

Alternatively, use the Makefile targets:

```bash
# Default vars are fine for quick start
make -C . all

# Or override variables
make -C . all NAMESPACE=mattermost MM_HOST=team.viduli.dev \
  MM_DB_USER=mattermost_user MM_DB_PASS=PassWDPG MM_DB_NAME=mattermost \
  MINIO_ACCESS_KEY=minioadmin MINIO_SECRET_KEY=minioadmin

# Inspect status anytime
make -C . status
```
```








## Links

https://www.digitalocean.com/community/tutorials/how-to-deploy-postgres-to-kubernetes-cluster

https://kubernetes.github.io/ingress-nginx/deploy/

https://github.com/mattermost/mattermost-helm/blob/master/charts/mattermost-operator/values.yaml
 
Mattermost Operator CRD reference: `https://docs.mattermost.com/deployment-guide/server/deploy-kubernetes.html`