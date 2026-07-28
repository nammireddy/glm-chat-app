#!/usr/bin/env bash
###############################################################################
# GLM Chat Application — Full Deployment Script
#
# This script is idempotent: safe to re-run at any point.
# It provisions infrastructure, builds images, and deploys all services.
#
# Usage:
#   ./scripts/deploy.sh [--skip-infra] [--skip-build] [--skip-deploy]
###############################################################################
set -euo pipefail

# --- Color helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/infra/terraform"
HELM_DIR="${ROOT_DIR}/helm"

SKIP_INFRA=false
SKIP_BUILD=false
SKIP_DEPLOY=false

for arg in "$@"; do
  case $arg in
    --skip-infra)  SKIP_INFRA=true ;;
    --skip-build)  SKIP_BUILD=true ;;
    --skip-deploy) SKIP_DEPLOY=true ;;
    *) err "Unknown argument: $arg"; exit 1 ;;
  esac
done

###############################################################################
# 1. Prerequisites Check
###############################################################################
info "Checking prerequisites..."

REQUIRED_TOOLS=(terraform helm kubectl aws docker)
for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    err "Required tool not found: $tool"
    exit 1
  fi
done

# Verify AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  err "AWS credentials not configured or expired. Run 'aws configure' or set environment variables."
  exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(cd "$TF_DIR" && terraform output -raw 2>/dev/null region || echo "us-east-1")

ok "All prerequisites satisfied (AWS Account: ${AWS_ACCOUNT_ID})"

###############################################################################
# 2. Terraform — Infrastructure Provisioning
###############################################################################
if [ "$SKIP_INFRA" = false ]; then
  info "Initializing Terraform..."
  cd "$TF_DIR"

  terraform init -upgrade

  info "Planning Terraform changes..."
  terraform plan -out=tfplan

  info "Applying Terraform..."
  terraform apply tfplan
  rm -f tfplan

  ok "Infrastructure provisioned successfully."
else
  warn "Skipping infrastructure provisioning (--skip-infra)"
fi

###############################################################################
# 3. Configure kubectl
###############################################################################
info "Updating kubeconfig for EKS cluster..."

cd "$TF_DIR"
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
CLUSTER_REGION=$(terraform output -raw 2>/dev/null region || echo "us-east-1")

aws eks update-kubeconfig \
  --region "$CLUSTER_REGION" \
  --name "$CLUSTER_NAME" \
  --alias "$CLUSTER_NAME"

ok "kubeconfig updated for cluster: ${CLUSTER_NAME}"

###############################################################################
# 4. Install Karpenter
###############################################################################
info "Installing/upgrading Karpenter..."

KARPENTER_VERSION="1.0.0"
KARPENTER_ROLE_ARN=$(terraform output -raw karpenter_controller_role_arn)

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --namespace kube-system \
  --version "$KARPENTER_VERSION" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${KARPENTER_ROLE_ARN}" \
  --wait --timeout 5m

ok "Karpenter installed (v${KARPENTER_VERSION})"

###############################################################################
# 5. Apply Karpenter NodePools, EC2NodeClass, NTH, DCGM, prometheus-adapter
###############################################################################
info "Applying Karpenter NodePool and EC2NodeClass manifests..."
kubectl apply -f "${ROOT_DIR}/infra/k8s/karpenter/"

info "Applying Node Termination Handler..."
kubectl apply -f "${ROOT_DIR}/infra/k8s/nth/"

info "Applying DCGM Exporter DaemonSet..."
kubectl apply -f "${ROOT_DIR}/infra/k8s/dcgm/"

info "Applying Prometheus Adapter config..."
kubectl apply -f "${ROOT_DIR}/infra/k8s/prometheus-adapter/"

ok "Cluster add-ons applied."

###############################################################################
# 6. Install kube-prometheus-stack
###############################################################################
info "Installing/upgrading kube-prometheus-stack..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values "${HELM_DIR}/kube-prometheus-stack/values.yaml" \
  --wait --timeout 10m

ok "kube-prometheus-stack installed."

###############################################################################
# 7. Apply Fluent Bit and Alertmanager configs
###############################################################################
info "Applying Fluent Bit DaemonSet..."
kubectl apply -f "${ROOT_DIR}/infra/k8s/fluent-bit/"

info "Applying Alertmanager rules..."
kubectl apply -f "${ROOT_DIR}/infra/k8s/alertmanager/"

ok "Logging and alerting configured."

###############################################################################
# 8. Build and Push Docker Images
###############################################################################
if [ "$SKIP_BUILD" = false ]; then
  info "Logging into ECR..."
  aws ecr get-login-password --region "$CLUSTER_REGION" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${CLUSTER_REGION}.amazonaws.com"

  GIT_SHA=$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "latest")

  SERVICES=(chat-service inference-service rag-service embedding-service confidence-scorer frontend)
  SERVICE_DIRS=(services/chat-service services/inference-service services/rag-service services/embedding-service services/confidence-scorer frontend)

  for i in "${!SERVICES[@]}"; do
    SVC="${SERVICES[$i]}"
    SVC_DIR="${SERVICE_DIRS[$i]}"
    ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${CLUSTER_REGION}.amazonaws.com/glm-chat/${SVC}"
    IMAGE_TAG="sha-${GIT_SHA}"

    info "Building ${SVC} (tag: ${IMAGE_TAG})..."
    docker build -t "${ECR_REPO}:${IMAGE_TAG}" "${ROOT_DIR}/${SVC_DIR}"

    info "Pushing ${SVC}..."
    docker push "${ECR_REPO}:${IMAGE_TAG}"

    ok "${SVC} pushed → ${ECR_REPO}:${IMAGE_TAG}"
  done
else
  warn "Skipping Docker build (--skip-build)"
  GIT_SHA=$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "latest")
fi

###############################################################################
# 9. Deploy Helm Charts
###############################################################################
if [ "$SKIP_DEPLOY" = false ]; then
  info "Deploying Helm charts..."

  IMAGE_TAG="sha-${GIT_SHA}"
  ECR_PREFIX="${AWS_ACCOUNT_ID}.dkr.ecr.${CLUSTER_REGION}.amazonaws.com/glm-chat"

  # Fetch Terraform outputs for Helm values
  CERT_ARN=$(cd "$TF_DIR" && terraform output -raw acm_certificate_arn)
  REDIS_ENDPOINT=$(cd "$TF_DIR" && terraform output -raw redis_primary_endpoint)
  REDIS_PORT=$(cd "$TF_DIR" && terraform output -raw redis_port)
  RDS_ENDPOINT=$(cd "$TF_DIR" && terraform output -raw rds_cluster_endpoint)
  EFS_ID=$(cd "$TF_DIR" && terraform output -raw efs_file_system_id)
  EFS_AP_ID=$(cd "$TF_DIR" && terraform output -raw efs_access_point_id)
  CHAT_ROLE_ARN=$(cd "$TF_DIR" && terraform output -raw irsa_chat_service_role_arn)
  RAG_ROLE_ARN=$(cd "$TF_DIR" && terraform output -raw irsa_rag_service_role_arn)
  INFERENCE_ROLE_ARN=$(cd "$TF_DIR" && terraform output -raw irsa_inference_service_role_arn)
  DOMAIN_NAME=$(cd "$TF_DIR" && terraform output -raw 2>/dev/null acm_certificate_domain_name || echo "")

  # --- Inference Service ---
  helm upgrade --install inference-service "${HELM_DIR}/inference-service" \
    --namespace glm-chat --create-namespace \
    --set "image.repository=${ECR_PREFIX}/inference-service" \
    --set "image.tag=${IMAGE_TAG}" \
    --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${INFERENCE_ROLE_ARN}" \
    --set "efs.fileSystemId=${EFS_ID}" \
    --set "efs.accessPointId=${EFS_AP_ID}" \
    --values "${HELM_DIR}/inference-service/values-prod.yaml" \
    --wait --timeout 10m

  # --- Embedding Service ---
  helm upgrade --install embedding-service "${HELM_DIR}/embedding-service" \
    --namespace glm-chat \
    --set "image.repository=${ECR_PREFIX}/embedding-service" \
    --set "image.tag=${IMAGE_TAG}" \
    --values "${HELM_DIR}/embedding-service/values-prod.yaml" \
    --wait --timeout 5m

  # --- RAG Service ---
  helm upgrade --install rag-service "${HELM_DIR}/rag-service" \
    --namespace glm-chat \
    --set "image.repository=${ECR_PREFIX}/rag-service" \
    --set "image.tag=${IMAGE_TAG}" \
    --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${RAG_ROLE_ARN}" \
    --set "env.PGHOST=${RDS_ENDPOINT}" \
    --values "${HELM_DIR}/rag-service/values-prod.yaml" \
    --wait --timeout 5m

  # --- Confidence Scorer ---
  helm upgrade --install confidence-scorer "${HELM_DIR}/confidence-scorer" \
    --namespace glm-chat \
    --set "image.repository=${ECR_PREFIX}/confidence-scorer" \
    --set "image.tag=${IMAGE_TAG}" \
    --values "${HELM_DIR}/confidence-scorer/values-prod.yaml" \
    --wait --timeout 5m

  # --- Chat Service ---
  helm upgrade --install chat-service "${HELM_DIR}/chat-service" \
    --namespace glm-chat \
    --set "image.repository=${ECR_PREFIX}/chat-service" \
    --set "image.tag=${IMAGE_TAG}" \
    --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${CHAT_ROLE_ARN}" \
    --set "ingress.certificateArn=${CERT_ARN}" \
    --set "ingress.host=${DOMAIN_NAME}" \
    --values "${HELM_DIR}/chat-service/values-prod.yaml" \
    --wait --timeout 5m

  # --- Frontend ---
  helm upgrade --install frontend "${HELM_DIR}/frontend" \
    --namespace glm-chat \
    --set "image.repository=${ECR_PREFIX}/frontend" \
    --set "image.tag=${IMAGE_TAG}" \
    --values "${HELM_DIR}/frontend/values-prod.yaml" \
    --wait --timeout 5m

  ok "All Helm charts deployed."
else
  warn "Skipping Helm deployment (--skip-deploy)"
fi

###############################################################################
# 10. Health Checks
###############################################################################
info "Running basic health checks..."

HEALTH_OK=true

# Check all pods in the glm-chat namespace are Running or Completed
NOT_READY=$(kubectl get pods -n glm-chat --no-headers 2>/dev/null | grep -v -E "Running|Completed" || true)
if [ -n "$NOT_READY" ]; then
  warn "Some pods are not ready:"
  echo "$NOT_READY"
  HEALTH_OK=false
fi

# Check inference service endpoint
if kubectl get svc inference-service -n glm-chat &>/dev/null; then
  ok "inference-service Service exists."
else
  warn "inference-service Service not found."
  HEALTH_OK=false
fi

# Check chat-service readiness
if kubectl get svc chat-service -n glm-chat &>/dev/null; then
  ok "chat-service Service exists."
else
  warn "chat-service Service not found."
  HEALTH_OK=false
fi

echo ""
if [ "$HEALTH_OK" = true ]; then
  ok "=============================="
  ok " Deployment completed successfully!"
  ok "=============================="
  echo ""
  info "Cluster: ${CLUSTER_NAME}"
  info "Domain:  ${DOMAIN_NAME:-'(not configured)'}"
  info "Image tag: sha-${GIT_SHA}"
else
  warn "=============================="
  warn " Deployment completed with warnings."
  warn " Check pod status: kubectl get pods -n glm-chat"
  warn "=============================="
  exit 1
fi
