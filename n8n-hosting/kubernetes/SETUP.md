# n8n Kubernetes Deployment Setup Guide

This guide documents all the steps needed to deploy n8n to AWS EKS with automatic CI/CD.

## Prerequisites

- AWS CLI configured with appropriate credentials
- `eksctl` installed
- `kubectl` installed
- GitHub CLI (`gh`) installed
- A forked n8n repository

## One-Time Infrastructure Setup

### 1. Create EKS Cluster and Install Required Components

Run the automated setup script:

```bash
cd n8n-hosting/kubernetes
./setup-eks-cluster.sh
```

This script will:
- ✅ Create an EKS cluster with managed nodes
- ✅ Install the AWS EBS CSI driver for persistent storage
- ✅ Create the `gp3` StorageClass
- ✅ Configure kubectl to connect to your cluster
- ✅ Save cluster information to `cluster-info.txt`

**Default Configuration:**
- Region: `us-west-2`
- Cluster Name: `n8n`
- Instance Type: `t3.medium`
- Node Count: `3`

### 2. Set GitHub Secrets

Set the required secrets for CI/CD (the setup script shows these commands):

```bash
cd /path/to/your/n8n/fork

# AWS & EKS Configuration
echo "us-west-2" | gh secret set AWS_REGION
echo "n8n" | gh secret set EKS_CLUSTER_NAME
gh secret set AWS_ACCESS_KEY_ID
gh secret set AWS_SECRET_ACCESS_KEY

# n8n Configuration
openssl rand -hex 32 | gh secret set N8N_ENCRYPTION_KEY
openssl rand -hex 32 | gh secret set N8N_RUNNERS_AUTH_TOKEN
openssl rand -base64 32 | gh secret set POSTGRES_PASSWORD

# Docker Hub (for pushing images)
gh secret set DOCKER_USERNAME
gh secret set DOCKER_PASSWORD

# Optional: For AI evaluation workflow
gh secret set EVALS_ANTHROPIC_KEY
gh secret set EVALS_LANGSMITH_API_KEY
gh secret set EVALS_LANGSMITH_ENDPOINT
```

### 3. Modify Kubernetes Manifests (if needed)

The manifests in this directory are configured for:
- **PostgreSQL**: 20Gi storage (gp3), 512Mi-2Gi memory
- **Redis**: 10Gi storage (gp3)
- **n8n**: 2Gi storage (gp3)
- **Workers**: 3 replicas
- **Runners**: 2 replicas

Adjust resource requests/limits in the YAML files if needed for your workload.

## CI/CD Pipeline

### How It Works

1. **Push to `master` branch** triggers two workflows:
   - **Test Master**: Runs unit tests and linting
   - **Docker: Build and Push**: Builds Docker images and deploys to EKS

2. **Docker workflow**:
   - Builds n8n and runner images for AMD64 and ARM64
   - Tags images as `:latest`
   - Pushes to GitHub Container Registry (GHCR) and Docker Hub
   - Deploys to EKS cluster with updated images

3. **Deployment strategy**:
   - If namespace doesn't exist → Initial deployment
   - If namespace exists with healthy PVCs → Rolling update
   - If namespace exists with unbound PVCs → Force delete and redeploy

### Monitoring Deployments

```bash
# Watch GitHub Actions
gh run watch

# Check pods in Kubernetes
kubectl get pods -n n8n

# View logs
kubectl logs -f deployment/n8n-main -n n8n
kubectl logs -f deployment/n8n-worker -n n8n
kubectl logs -f deployment/n8n-runner -n n8n
```

## Local Testing (Before Pushing)

### Test Deployment Locally

Use the test script to verify deployment without CI/CD:

```bash
cd n8n-hosting/kubernetes
./test-deployment.sh
```

This will:
- Verify cluster connection
- Check storage classes
- Create namespace and secrets
- Deploy all components
- Wait for pods to be ready
- Show status and access instructions

### Verify Deployment Health

```bash
./verify.sh
```

This checks:
- Pod status
- Service connectivity
- Health endpoints
- Resource usage

### Clean Up

To remove the deployment:

```bash
./undeploy.sh
```

Or to completely delete the namespace:

```bash
kubectl delete namespace n8n --force --grace-period=0
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     LoadBalancer                         │
│                    (EKS Service)                         │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
              ┌────────────────┐
              │   n8n-main     │
              │  (1 replica)   │
              │                │
              │  - Webhooks    │
              │  - UI          │
              │  - Triggers    │
              └────┬───────┬───┘
                   │       │
      ┌────────────┘       └──────────────┐
      │                                    │
      ▼                                    ▼
┌─────────────┐                    ┌──────────────┐
│ n8n-worker  │                    │ n8n-runner   │
│ (3 replicas)│                    │ (2 replicas) │
│             │                    │              │
│ - Execute   │                    │ - JS Runner  │
│   workflows │                    │ - Code nodes │
└──────┬──────┘                    └──────┬───────┘
       │                                  │
       ├──────────────┬───────────────────┤
       │              │                   │
       ▼              ▼                   ▼
┌──────────┐   ┌────────────┐     ┌────────────┐
│PostgreSQL│   │   Redis    │     │  AWS EBS   │
│  (1pod)  │   │  (1 pod)   │     │  Volumes   │
│          │   │            │     │  (gp3)     │
│ - Main DB│   │ - Queue    │     │            │
└──────────┘   └────────────┘     └────────────┘
```

## Configuration Details

### Storage Classes

- **gp3**: Modern AWS EBS volume type with better performance and cost
  - VolumeBindingMode: `WaitForFirstConsumer` (volumes created when pods start)
  - Encryption: Enabled
  - Expansion: Allowed

### Secrets

All secrets are injected at deployment time via GitHub Actions:

**postgres-secret:**
- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- `POSTGRES_NON_ROOT_USER`, `POSTGRES_NON_ROOT_PASSWORD`

**n8n-secret:**
- `N8N_ENCRYPTION_KEY`: For encrypting credentials in DB
- `N8N_RUNNERS_AUTH_TOKEN`: For runner authentication
- Queue/Redis configuration
- Runner configuration

### Networking

- **n8n Service**: LoadBalancer on port 5678 (main UI/API)
- **n8n-main Service**: ClusterIP on port 5679 (task broker)
- **postgres-service**: ClusterIP on port 5432
- **redis-service**: ClusterIP on port 6379

## Troubleshooting

### PVCs Stuck in Pending

This is **expected** with `WaitForFirstConsumer` binding mode. PVCs only bind when a pod tries to use them.

If PVCs remain pending after pods start:
```bash
kubectl describe pvc -n n8n
kubectl get events -n n8n
```

### Pods in ImagePullBackOff

Check if images were built and pushed:
```bash
# Check GHCR
docker pull ghcr.io/<your-username>/n8n:latest

# Check workflow logs
gh run view --log
```

### Pods in CrashLoopBackOff

Check pod logs:
```bash
kubectl logs -n n8n <pod-name>
kubectl describe pod -n n8n <pod-name>
```

### Runner Connection Issues

Runners need to connect to n8n-main on port 5679 using `http://` scheme:
```bash
kubectl logs -n n8n -l service=n8n-runner
```

## Cost Optimization

### Development/Testing

```yaml
# Minimal setup:
- Node Type: t3.small
- Node Count: 2
- PostgreSQL: 10Gi, 256Mi memory
- Redis: 5Gi
- n8n: 1Gi
- Workers: 1 replica
- Runners: 1 replica
```

### Production

```yaml
# Recommended:
- Node Type: t3.medium or larger
- Node Count: 3-5 (with autoscaling)
- PostgreSQL: 20-100Gi, 1-4Gi memory
- Redis: 10-20Gi
- n8n: 2-5Gi
- Workers: 3-10 replicas (scale with load)
- Runners: 2-5 replicas
```

## Maintenance

### Updating n8n

Push to master → CI/CD automatically builds and deploys latest code

### Scaling

```bash
# Scale workers
kubectl scale deployment n8n-worker -n n8n --replicas=5

# Scale runners
kubectl scale deployment n8n-runner -n n8n --replicas=4
```

### Backups

PostgreSQL data is on persistent volumes. To backup:

```bash
# Export workflows
kubectl exec -it -n n8n deployment/n8n-main -- n8n export:workflow --all

# Backup PostgreSQL
kubectl exec -it -n n8n deployment/postgres -- pg_dump -U postgres n8n > backup.sql
```

### Accessing n8n

```bash
# Get LoadBalancer URL
kubectl get svc n8n -n n8n

# Or port-forward for local access
kubectl port-forward -n n8n svc/n8n 5678:5678
# Then open: http://localhost:5678
```

## Security Notes

1. **Encryption Key**: Keep `N8N_ENCRYPTION_KEY` safe - needed to decrypt credentials
2. **LoadBalancer**: Consider adding SSL/TLS termination
3. **Network Policies**: Add Kubernetes NetworkPolicies for pod isolation
4. **RBAC**: Review service account permissions
5. **Secrets Management**: Consider using AWS Secrets Manager or HashiCorp Vault

## Support Files

- `setup-eks-cluster.sh`: Initial cluster setup
- `test-deployment.sh`: Local deployment testing
- `verify.sh`: Health check script
- `undeploy.sh`: Clean removal script
- `*.yaml`: Kubernetes manifests

## Additional Resources

- [n8n Documentation](https://docs.n8n.io/)
- [EKS User Guide](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

