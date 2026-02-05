Miscellaneous utility scripts for Xano instance management and deployment operations.

This repository contains standalone shell scripts that assist with common administrative tasks for Xano cloud infrastructure. These scripts are designed to be portable and self-contained, requiring only standard CLI tools (kubectl, gcloud, etc.) without dependencies on the internal ops CLI or other Xano-specific tooling.

## Scripts

### create-service-account-kubeconfig.sh

Creates a Kubernetes service account with cluster-admin privileges and generates a standalone kubeconfig file.

**Use case:** Generate a kubeconfig that can be shared with team members or external parties who need kubectl access to a cluster without requiring access to the ops CLI or GCP credentials.

**Usage:**
```bash
./create-service-account-kubeconfig.sh [--context <context-name>] [-n <namespace>] [-private]
```

**Options:**
- `--context` - Kubernetes context to use (default: current context)
- `-n` - Namespace for service account (default: xano)
- `-private` - Use cluster's private/internal endpoint instead of public

**Example:**
```bash
# Generate kubeconfig for current context
./create-service-account-kubeconfig.sh > cluster.kubeconfig

# Generate kubeconfig for a specific context with private endpoint
./create-service-account-kubeconfig.sh --context gke_xano-prod_us-central1_cluster-1 -private > cluster.kubeconfig
```

**Prerequisites:**
- kubectl configured and authenticated to the target cluster
- Cluster admin permissions to create ServiceAccount, Secret, and ClusterRoleBinding
