#!/bin/bash
#
# Creates a Kubernetes service account with cluster-admin privileges and generates a kubeconfig file.
#
# Usage: ./create-service-account-kubeconfig.sh [--context <context-name>] [-n <namespace>] [-private]
#
# Options:
#   --context   Kubernetes context to use (default: current context)
#   -n          Namespace for service account (default: xano)
#   -private    Use cluster's private/internal endpoint instead of public
#
# Prerequisites:
#   - kubectl configured and authenticated to the target cluster
#   - Cluster admin permissions to create ServiceAccount, Secret, and ClusterRoleBinding
#

set -euo pipefail

CONTEXT=""
NAMESPACE="xano"
USE_PRIVATE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --context)
      CONTEXT="$2"
      shift 2
      ;;
    -n)
      NAMESPACE="$2"
      shift 2
      ;;
    -private)
      USE_PRIVATE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--context <context-name>] [-n <namespace>] [-private]"
      echo ""
      echo "Creates a Kubernetes service account with cluster-admin privileges"
      echo "and generates a kubeconfig file for it."
      echo ""
      echo "Options:"
      echo "  --context   Kubernetes context to use (default: current context)"
      echo "  -n          Namespace for service account (default: xano)"
      echo "  -private    Use cluster's private/internal endpoint instead of public"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Derived variables
SERVICE_ACCOUNT_NAME="${NAMESPACE}-admin"
SECRET_NAME="${NAMESPACE}-admin-token"

# Build kubectl command with optional context
KUBECTL="kubectl"
if [[ -n "$CONTEXT" ]]; then
  KUBECTL="kubectl --context $CONTEXT"
fi

echo "Creating namespace '$NAMESPACE' if it doesn't exist..." >&2
$KUBECTL create namespace "$NAMESPACE" --dry-run=client -o yaml | $KUBECTL apply -f - >&2

echo "Creating service account and RBAC resources..." >&2
$KUBECTL apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: ${NAMESPACE}
---
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SERVICE_ACCOUNT_NAME}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${SERVICE_ACCOUNT_NAME}-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: ${NAMESPACE}
EOF

echo "Waiting for secret to be populated..." >&2
for i in {1..30}; do
  TOKEN=$($KUBECTL get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null || true)
  if [[ -n "$TOKEN" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$TOKEN" ]]; then
  echo "Error: Timed out waiting for token to be populated in secret" >&2
  exit 1
fi

echo "Extracting credentials..." >&2
TOKEN=$(echo "$TOKEN" | base64 -d)
CA_CERT=$($KUBECTL get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.ca\.crt}')

if [[ "$USE_PRIVATE" == true ]]; then
  # Get the private endpoint from the kubernetes service
  PRIVATE_IP=$($KUBECTL get endpoints kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}')
  SERVER="https://${PRIVATE_IP}:443"
else
  SERVER=$($KUBECTL config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}')
fi

if [[ -z "$SERVER" ]]; then
  echo "Error: Could not determine cluster server URL" >&2
  exit 1
fi

echo "" >&2
echo "=== Generating kubeconfig ===" >&2
echo "" >&2

KUBECONFIG_CONTENT=$(cat <<EOF
apiVersion: v1
kind: Config
clusters:
- name: cluster
  cluster:
    certificate-authority-data: ${CA_CERT}
    server: ${SERVER}
contexts:
- name: user@cluster
  context:
    cluster: cluster
    user: user
current-context: user@cluster
users:
- name: user
  user:
    token: ${TOKEN}
EOF
)

echo "$KUBECONFIG_CONTENT"
echo "" >&2
