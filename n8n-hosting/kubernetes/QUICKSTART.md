# n8n Queue Mode - Quick Start

Deploy production-ready n8n with PostgreSQL, Redis, workers, and task runners in 5 minutes.

## Prerequisites

- AWS account with EKS cluster OR existing Kubernetes cluster
- `kubectl` installed and configured
- `eksctl` installed (if creating new EKS cluster)

## Option 1: Automated Deployment (Recommended)

### 1. Generate Secrets

```bash
# Generate all required secrets 
echo "Copy these values into your secret files:"
echo ""
echo "For postgres-secret.yaml:"
echo "  POSTGRES_PASSWORD: $(openssl rand -base64 24)"
echo ""
echo "For n8n-secret.yaml:"
echo "  N8N_ENCRYPTION_KEY: $(openssl rand -base64 32)"
echo "  N8N_RUNNERS_AUTH_TOKEN: $(openssl rand -base64 24)"
```

### 2. Update Secret Files

Edit `postgres-secret.yaml` and `n8n-secret.yaml` with the generated values above.

### 3. Deploy

```bash
./deploy.sh
```

That's it! The script will:
- ✅ Validate your secrets are configured
- ✅ Create namespace and secrets
- ✅ Deploy PostgreSQL and Redis
- ✅ Deploy n8n main instance
- ✅ Deploy workers and task runners
- ✅ Show you the access URL

## Option 2: Manual Deployment

See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed step-by-step instructions.

## Access n8n

Once deployed, get your access URL:

```bash
kubectl get svc n8n -n n8n
```

Access n8n at: `http://<EXTERNAL-IP>:5678`

## Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n n8n

# Expected output:
# NAME                          READY   STATUS    RESTARTS   AGE
# postgres-xxxx                 1/1     Running   0          5m
# redis-xxxx                    1/1     Running   0          5m
# n8n-main-xxxx                 1/1     Running   0          3m
# n8n-worker-xxxx (x3)          1/1     Running   0          1m
# n8n-runner-xxxx (x2)          1/1     Running   0          1m
```

## Test Queue Mode

1. Create a simple workflow in n8n UI
2. Add a Schedule Trigger (runs every minute)
3. Add some nodes (HTTP Request, Code, etc.)
4. Activate the workflow
5. Check worker logs to see execution:

```bash
kubectl logs -f deployment/n8n-worker -n n8n
```

You should see workers picking up and executing jobs!

## Scale Your Deployment

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

### Multi-Main HA Setup
```bash
# Add to n8n-secret.yaml:
# N8N_MULTI_MAIN_SETUP_ENABLED: "true"

# Apply changes
kubectl apply -f n8n-secret.yaml
kubectl rollout restart deployment/n8n-main -n n8n

# Scale main instances
kubectl scale deployment n8n-main -n n8n --replicas=2
```

## Common Commands

```bash
# View logs
kubectl logs -f deployment/n8n-main -n n8n
kubectl logs -f deployment/n8n-worker -n n8n
kubectl logs -f deployment/n8n-runner -n n8n

# Check resource usage
kubectl top pods -n n8n

# Restart a component
kubectl rollout restart deployment/n8n-worker -n n8n

# Get all resources
kubectl get all -n n8n

# Describe a pod for troubleshooting
kubectl describe pod <pod-name> -n n8n
```

## Troubleshooting

### Workers not picking up jobs?

```bash
# Check Redis connectivity
kubectl exec -it deployment/n8n-worker -n n8n -- nc -zv redis-service 6379

# Check encryption key matches
kubectl get secret n8n-secret -n n8n -o yaml | grep N8N_ENCRYPTION_KEY
```

### Runners not connecting?

```bash
# Check runner logs
kubectl logs deployment/n8n-runner -n n8n

# Verify task broker is accessible
kubectl exec -it deployment/n8n-runner -n n8n -- nc -zv n8n-main 5679
```

### Database issues?

```bash
# Test PostgreSQL connectivity
kubectl exec -it deployment/n8n-main -n n8n -- nc -zv postgres-service 5432

# Check PostgreSQL logs
kubectl logs deployment/postgres -n n8n
```

## Uninstall

```bash
# Remove all n8n resources
./undeploy.sh
```

## Architecture Overview

```
┌─────────────────────────────────────┐
│        AWS Load Balancer (ELB)      │
└──────────────┬──────────────────────┘
               │
               ↓
┌──────────────────────────────────────┐
│      n8n Main Instance (1 pod)       │
│   - Handles UI/API/Webhooks          │
│   - Sends jobs to Redis queue        │
└──────────┬───────────────────────────┘
           │
           ↓
┌──────────────────────────────────────┐
│          Redis (Message Queue)       │
└──────────┬───────────────────────────┘
           │
           ↓
┌──────────────────────────────────────┐
│      n8n Workers (3 pods)            │
│   - Pick up jobs from Redis          │
│   - Execute workflows                │
│   - Send Code tasks to runners       │
└──────────┬───────────────────────────┘
           │
           ↓
┌──────────────────────────────────────┐
│      n8n Task Runners (2 pods)       │
│   - Execute Code node scripts        │
│   - Isolated sandboxed environment   │
└──────────────────────────────────────┘
           │
           ↓
┌──────────────────────────────────────┐
│          PostgreSQL Database         │
│   - Stores workflows & executions    │
│   - Stores credentials (encrypted)   │
└──────────────────────────────────────┘
```

## What You Get

✅ **Queue Mode**: Workflows executed by dedicated worker processes
✅ **Horizontal Scaling**: Scale workers and runners independently
✅ **Task Runners**: Isolated Code node execution (JavaScript & Python)
✅ **High Availability**: Ready for multi-main setup
✅ **Production Database**: PostgreSQL (not SQLite)
✅ **Message Queue**: Redis for job distribution
✅ **Health Checks**: Built-in liveness and readiness probes
✅ **Resource Limits**: Proper resource requests and limits configured

## Next Steps

1. ✅ Deploy using `./deploy.sh`
2. ✅ Access n8n UI and set up admin account
3. ✅ Create your first workflow
4. ✅ Test Code node with allowed modules
5. ✅ Monitor logs to see queue mode in action
6. 🚀 Set up your own domain and HTTPS
7. 🚀 Configure backups for PostgreSQL
8. 🚀 Set up monitoring (Prometheus/Grafana)
9. 🚀 Configure autoscaling (HPA)

## Documentation

- **Quick Start**: This file
- **Full Deployment Guide**: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- **Secrets Setup**: [SECRETS_TEMPLATE.md](SECRETS_TEMPLATE.md)
- **n8n Documentation**: https://docs.n8n.io/hosting/scaling/queue-mode/

## Support

- n8n Community Forum: https://community.n8n.io/
- n8n Documentation: https://docs.n8n.io/
- GitHub Issues: https://github.com/n8n-io/n8n/issues

## Cost Estimate (AWS)

Minimum viable setup (~$150-200/month):
- EKS Cluster: ~$75/month
- 3x t3.medium nodes: ~$100/month
- Load Balancer: ~$20/month
- Storage (EBS): ~$10/month

For production, consider:
- Using RDS for PostgreSQL
- Using ElastiCache for Redis
- Using spot instances for workers
- Setting up proper monitoring

