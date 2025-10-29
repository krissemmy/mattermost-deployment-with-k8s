# Configurable variables (override with: make all NAMESPACE=foo)
NAMESPACE ?= mattermost
INGRESS_RELEASE ?= ingress-nginx
MM_OPERATOR_RELEASE ?= mattermost-operator
MM_HOST ?= team.viduli.dev

# Database
MM_DB_USER ?= mattermost_user
MM_DB_PASS ?= PassWDPG
MM_DB_HOST ?= postgres
MM_DB_NAME ?= mattermost
MM_DB_PORT ?= 5432

# MinIO
MINIO_ACCESS_KEY ?= minioadmin
MINIO_SECRET_KEY ?= minioadmin

ROOT_DIR := $(abspath .)

.PHONY: all namespace ingress operator postgres minio bucket secrets mattermost status

all: namespace ingress operator postgres minio bucket secrets mattermost status

namespace:
	kubectl create namespace $(NAMESPACE) 2>/dev/null || true

ingress:
	helm upgrade --install $(INGRESS_RELEASE) ingress-nginx \
	  --repo https://kubernetes.github.io/ingress-nginx \
	  --namespace $(NAMESPACE) --create-namespace

operator:
	helm repo add mattermost https://helm.mattermost.com >/dev/null 2>&1 || true
	helm repo update >/dev/null 2>&1 || true
	helm upgrade --install $(MM_OPERATOR_RELEASE) mattermost/mattermost-operator \
	  -n $(NAMESPACE) -f $(ROOT_DIR)/config.yaml

postgres:
	kubectl apply -n $(NAMESPACE) -f $(ROOT_DIR)/postgres/postgres-configmap.yaml
	kubectl apply -n $(NAMESPACE) -f $(ROOT_DIR)/postgres/postgres-pv.yaml
	kubectl apply -n $(NAMESPACE) -f $(ROOT_DIR)/postgres/postgres-claim.yaml
	kubectl apply -n $(NAMESPACE) -f $(ROOT_DIR)/postgres/postgres-deployment.yaml
	kubectl apply -n $(NAMESPACE) -f $(ROOT_DIR)/postgres/postgres-service.yaml
	- kubectl -n $(NAMESPACE) rollout status deploy/postgres --timeout=180s

minio:
	kubectl apply -n $(NAMESPACE) -f $(ROOT_DIR)/minio/minio-pv.yaml
	kubectl apply -n $(NAMESPACE) -f $(ROOT_DIR)/minio/minio-pvc.yaml
	kubectl apply -n $(NAMESPACE) -f $(ROOT_DIR)/minio/minio-deployment.yaml
	kubectl apply -n $(NAMESPACE) -f $(ROOT_DIR)/minio/minio-service.yaml
	- kubectl -n $(NAMESPACE) rollout status deploy/minio --timeout=180s

bucket:
	kubectl apply -n $(NAMESPACE) -f $(ROOT_DIR)/minio/minio-bucket-job.yaml
	- kubectl -n $(NAMESPACE) wait --for=condition=complete --timeout=180s job/minio-create-bucket

secrets:
	# Database secret (DSN and connectivity check URL)
	kubectl -n $(NAMESPACE) create secret generic mattermost-db-credentials \
	  --from-literal=MM_SQLSETTINGS_DATASOURCE="postgres://$(MM_DB_USER):$(MM_DB_PASS)@$(MM_DB_HOST):$(MM_DB_PORT)/$(MM_DB_NAME)?sslmode=disable" \
	  --from-literal=DB_CONNECTION_CHECK_URL="postgres://$(MM_DB_HOST):$(MM_DB_PORT)/$(MM_DB_NAME)?sslmode=disable" \
	  --dry-run=client -o yaml | kubectl apply -f -
	# MinIO credentials secret for filestore
	kubectl -n $(NAMESPACE) create secret generic minio-credentials \
	  --from-literal=accesskey="$(MINIO_ACCESS_KEY)" \
	  --from-literal=secretkey="$(MINIO_SECRET_KEY)" \
	  --dry-run=client -o yaml | kubectl apply -f -

mattermost:
	@grep -q "host: $(MM_HOST)" $(ROOT_DIR)/mattermost-installation.yaml || \
	  echo "Warning: mattermost-installation.yaml host differs from MM_HOST=$(MM_HOST)."
	kubectl apply -n $(NAMESPACE) -f $(ROOT_DIR)/mattermost-installation.yaml

status:
	kubectl -n $(NAMESPACE) get pods -o wide

