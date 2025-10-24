# n8n Queue Mode Deployment Guide

This guide shows you how to deploy n8n on AWS EKS with PostgreSQL, Redis, queue mode, workers, and task runners.

## Architecture

```
Internet
  ↓
AWS Load Balancer (ELB)
  ↓
n8n Main (1 pod) ← handles UI/API/webhooks
  ↓
Redis (message queue)
  ↓
n8n Workers (3 pods) ← execute workflows
  ↓
n8n Task Runners (2 pods) ← execute Code node scripts
  ↓
PostgreSQL ← stores all data
```

## Prerequisites

1. Install required tools:
```bash
brew install awscli eksctl kubectl
```

2. Configure AWS CLI:
```bash
aws configure
```

## Step 1: Create EKS Cluster

```bash
# Create the cluster (takes 15-20 minutes)
eksctl create cluster --name n8n-production --region us-east-1

# Verify kubectl context is set
kubectl config current-context
```

## Step 2: Generate Secrets

Before deploying, you MUST generate secure random values:

```bash
# Generate encryption key
openssl rand -base64 32

# Generate runner auth token
openssl rand -base64 24

# Generate strong PostgreSQL password
openssl rand -base64 24
```

## Step 3: Configure Secrets

### Edit `postgres-secret.yaml`

Replace the placeholder values:
```yaml
stringData:
  POSTGRES_USER: n8n_user
  POSTGRES_PASSWORD: <YOUR_POSTGRES_PASSWORD_HERE>
  POSTGRES_DB: n8n
  POSTGRES_NON_ROOT_USER: n8n_user
  POSTGRES_NON_ROOT_PASSWORD: <YOUR_POSTGRES_PASSWORD_HERE>
```

### Edit `n8n-secret.yaml`

Replace these placeholder values:
```yaml
stringData:
  # CRITICAL: Use values generated above
  N8N_ENCRYPTION_KEY: "<YOUR_ENCRYPTION_KEY_FROM_STEP_2>"
  N8N_RUNNERS_AUTH_TOKEN: "<YOUR_RUNNER_AUTH_TOKEN_FROM_STEP_2>"
  
  # Optional: Set your domain
  # WEBHOOK_URL: "https://n8n.yourdomain.com"
  
  # Optional: Adjust timezone
  GENERIC_TIMEZONE: "America/New_York"
```

## Step 4: Deploy to Kubernetes

Deploy in the following order:

```bash
# 1. Create namespace
kubectl apply -f namespace.yaml

# 2. Create secrets
kubectl apply -f postgres-secret.yaml
kubectl apply -f n8n-secret.yaml

# 3. Create persistent volume claims
kubectl apply -f postgres-claim0-persistentvolumeclaim.yaml
kubectl apply -f n8n-claim0-persistentvolumeclaim.yaml
kubectl apply -f redis-claim0-persistentvolumeclaim.yaml

# 4. Deploy Redis and Postgres
kubectl apply -f redis-deployment.yaml
kubectl apply -f postgres-configmap.yaml
kubectl apply -f postgres-deployment.yaml
kubectl apply -f postgres-service.yaml

# 5. Wait for databases to be ready
kubectl wait --for=condition=ready pod -l service=postgres-n8n -n n8n --timeout=300s
kubectl wait --for=condition=ready pod -l service=redis -n n8n --timeout=300s

# 6. Deploy n8n main instance
kubectl apply -f n8n-deployment-queue-mode.yaml
kubectl apply -f n8n-service.yaml

# 7. Wait for main instance to be ready
kubectl wait --for=condition=ready pod -l service=n8n-main -n n8n --timeout=300s

# 8. Deploy workers and runners
kubectl apply -f n8n-worker-deployment.yaml
kubectl apply -f n8n-runner-deployment.yaml
```

## Step 5: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n n8n

# Expected output:
# NAME                          READY   STATUS    RESTARTS   AGE
# postgres-xxxx                 1/1     Running   0          5m
# redis-xxxx                    1/1     Running   0          5m
# n8n-main-xxxx                 1/1     Running   0          3m
# n8n-worker-xxxx               1/1     Running   0          1m
# n8n-worker-yyyy               1/1     Running   0          1m
# n8n-worker-zzzz               1/1     Running   0          1m
# n8n-runner-xxxx               1/1     Running   0          1m
# n8n-runner-yyyy               1/1     Running   0          1m

# Check logs
kubectl logs -f deployment/n8n-main -n n8n
kubectl logs -f deployment/n8n-worker -n n8n
kubectl logs -f deployment/n8n-runner -n n8n
```

## Step 6: Get Access URL

```bash
# Get the load balancer URL
kubectl get svc n8n -n n8n

# Output will show EXTERNAL-IP like:
# a1234567890.us-east-1.elb.amazonaws.com
```

Access n8n at: `http://<EXTERNAL-IP>:5678`

## Step 7: Set Up DNS (Optional)

Point your domain to the load balancer:

```bash
# Create a CNAME record:
n8n.yourdomain.com -> CNAME -> <EXTERNAL-IP from step 6>
```

Then update `n8n-secret.yaml` with your domain and redeploy:
```yaml
WEBHOOK_URL: "https://n8n.yourdomain.com"
```

## Scaling

### Scale Workers
```bash
# Scale to 5 workers
kubectl scale deployment n8n-worker -n n8n --replicas=5
```

### Scale Runners
```bash
# Scale to 4 runners
kubectl scale deployment n8n-runner -n n8n --replicas=4
```

### Multi-Main Setup (High Availability)
To run multiple main instances for HA:

1. Add to `n8n-secret.yaml`:
```yaml
N8N_MULTI_MAIN_SETUP_ENABLED: "true"
```

2. Scale main instances:
```bash
kubectl scale deployment n8n-main -n n8n --replicas=2
```

3. Enable session persistence in your load balancer (sticky sessions)

## Monitoring

### Check Queue Status
```bash
# Main instance logs show queue activity
kubectl logs -f deployment/n8n-main -n n8n | grep -i queue

# Worker logs show execution activity
kubectl logs -f deployment/n8n-worker -n n8n | grep -i execution
```

### Resource Usage
```bash
# Check resource usage
kubectl top pods -n n8n
```

### Health Checks
```bash
# Check health endpoints
kubectl exec -it deployment/n8n-main -n n8n -- curl localhost:5678/healthz
kubectl exec -it deployment/n8n-worker -n n8n -- curl localhost:5678/healthz
```

## Troubleshooting

### Workers not picking up jobs
1. Check Redis is accessible:
```bash
kubectl exec -it deployment/n8n-worker -n n8n -- nc -zv redis-service 6379
```

2. Verify encryption keys match:
```bash
kubectl describe secret n8n-secret -n n8n
```

### Task runners not connecting
1. Check runner logs:
```bash
kubectl logs deployment/n8n-runner -n n8n
```

2. Verify auth token matches:
```bash
kubectl exec -it deployment/n8n-runner -n n8n -- env | grep AUTH_TOKEN
```

### Database connection issues
```bash
# Test database connectivity
kubectl exec -it deployment/n8n-main -n n8n -- nc -zv postgres-service 5432

# Check postgres logs
kubectl logs deployment/postgres -n n8n
```

## Clean Up

To delete everything:
```bash
kubectl delete namespace n8n
```

Or delete individual components:
```bash
kubectl delete -f n8n-runner-deployment.yaml
kubectl delete -f n8n-worker-deployment.yaml
kubectl delete -f n8n-deployment-queue-mode.yaml
kubectl delete -f redis-deployment.yaml
kubectl delete -f postgres-deployment.yaml
# ... etc
```

## Production Recommendations

1. **Use RDS for PostgreSQL** instead of a pod for better reliability
2. **Use ElastiCache for Redis** instead of a pod
3. **Set up TLS/HTTPS** using AWS ALB Ingress Controller or cert-manager
4. **Enable monitoring** with Prometheus/Grafana
5. **Set up backups** for PostgreSQL and persistent volumes
6. **Use separate node groups** for different workloads (main/workers/db)
7. **Configure autoscaling** with Horizontal Pod Autoscaler (HPA)

## Resource Requirements

Minimum cluster size for this setup:
- **3 nodes** (t3.medium or larger)
- **8 GB RAM** total
- **4 vCPUs** total

Recommended for production:
- **5+ nodes** (t3.large or larger)
- **16+ GB RAM** total
- **8+ vCPUs** total

## Cost Optimization

- Start with 1 worker, scale up as needed
- Use spot instances for workers (they can be terminated safely)
- Use reserved instances for main and database nodes
- Monitor and adjust resource requests/limits

## Next Steps

1. ✅ Deploy the infrastructure
2. ✅ Access n8n UI and create first workflow
3. ✅ Test queue mode by creating workflows with multiple executions
4. ✅ Test Code node with allowed modules
5. ✅ Monitor worker and runner logs
6. ✅ Set up production-ready database (RDS)
7. ✅ Configure HTTPS/TLS
8. ✅ Set up monitoring and alerting

