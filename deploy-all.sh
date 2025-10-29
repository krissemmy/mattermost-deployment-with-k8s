#!/usr/bin/env bash
set -euo pipefail

# Configurable vars (override via env before running)
NAMESPACE=${NAMESPACE:-mattermost}
INGRESS_RELEASE=${INGRESS_RELEASE:-ingress-nginx}
MM_OPERATOR_RELEASE=${MM_OPERATOR_RELEASE:-mattermost-operator}
MM_HOST=${MM_HOST:-team.viduli.dev}

# Database defaults (should match postgres/postgres-configmap.yaml)
MM_DB_USER=${MM_DB_USER:-mattermost_user}
MM_DB_PASS=${MM_DB_PASS:-PassWDPG}
MM_DB_HOST=${MM_DB_HOST:-postgres}
MM_DB_NAME=${MM_DB_NAME:-mattermost}
MM_DB_PORT=${MM_DB_PORT:-5432}

# MinIO defaults
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:-minioadmin}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:-minioadmin}

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "[1/8] Creating namespace: ${NAMESPACE}"
kubectl create namespace "${NAMESPACE}" 2>/dev/null || true

echo "[2/8] Installing/Upgrading ingress-nginx"
helm upgrade --install "${INGRESS_RELEASE}" ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace "${NAMESPACE}" --create-namespace

echo "[3/8] Installing/Upgrading Mattermost Operator"
helm repo add mattermost https://helm.mattermost.com >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true
helm upgrade --install "${MM_OPERATOR_RELEASE}" mattermost/mattermost-operator \
  -n "${NAMESPACE}" -f "${ROOT_DIR}/config.yaml"

echo "[4/8] Deploying PostgreSQL"
kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/postgres/postgres-configmap.yaml"
kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/postgres/postgres-pv.yaml"
kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/postgres/postgres-claim.yaml"
kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/postgres/postgres-deployment.yaml"
kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/postgres/postgres-service.yaml"
kubectl -n "${NAMESPACE}" rollout status deploy/postgres --timeout=180s || true

echo "[5/8] Deploying MinIO"
kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/minio/minio-pv.yaml"
kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/minio/minio-pvc.yaml"
kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/minio/minio-deployment.yaml"
kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/minio/minio-service.yaml"
kubectl -n "${NAMESPACE}" rollout status deploy/minio --timeout=180s || true
kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/minio/minio-bucket-job.yaml"
kubectl -n "${NAMESPACE}" wait --for=condition=complete --timeout=180s job/minio-create-bucket || true

echo "[6/8] Creating/Updating Secrets"
# Database DSN secret
kubectl -n "${NAMESPACE}" create secret generic mattermost-db-credentials \
  --from-literal=MM_SQLSETTINGS_DATASOURCE="postgres://${MM_DB_USER}:${MM_DB_PASS}@${MM_DB_HOST}:${MM_DB_PORT}/${MM_DB_NAME}?sslmode=disable" \
  --from-literal=DB_CONNECTION_CHECK_URL="postgres://${MM_DB_HOST}:${MM_DB_PORT}/${MM_DB_NAME}?sslmode=disable" \
  --dry-run=client -o yaml | kubectl apply -f -

# MinIO access secret
kubectl -n "${NAMESPACE}" create secret generic minio-credentials \
  --from-literal=accesskey="${MINIO_ACCESS_KEY}" \
  --from-literal=secretkey="${MINIO_SECRET_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[7/8] Applying Mattermost installation"
# Ensure host in CR matches desired host
if ! grep -q "host: ${MM_HOST}" "${ROOT_DIR}/mattermost-installation.yaml"; then
  echo "Warning: mattermost-installation.yaml host differs from MM_HOST=${MM_HOST}. Edit file if needed."
fi
kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/mattermost-installation.yaml"

echo "[8/8] Waiting for Mattermost pods (best-effort)"
kubectl -n "${NAMESPACE}" get pods
echo "Done. Point DNS for ${MM_HOST} to your ingress controller."

