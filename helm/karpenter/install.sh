#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Karpenter v1.1.0 into the 'karpenter' namespace..."

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --namespace karpenter --create-namespace \
  --version "1.1.0" \
  -f "${SCRIPT_DIR}/values.yaml"

echo "Karpenter installation complete."
echo "Next steps:"
echo "  1. Apply NodePool and EC2NodeClass manifests from infra/k8s/karpenter/"
echo "  2. Verify controller pods are running: kubectl get pods -n karpenter"
