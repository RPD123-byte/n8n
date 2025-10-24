# n8n Queue Mode Deployment for Kubernetes

This directory contains Kubernetes manifests for deploying n8n in **queue mode** with PostgreSQL, Redis, workers, and task runners.

## 🚀 What's Included

This deployment provides a **production-ready n8n setup** with:

- ✅ **Queue Mode**: Workflow executions handled by dedicated worker processes
- ✅ **PostgreSQL**: Robust database backend (not SQLite)
- ✅ **Redis**: Message queue for job distribution
- ✅ **Workers**: Horizontally scalable workflow execution (3 replicas)
- ✅ **Task Runners**: Isolated Code node execution (2 replicas)
- ✅ **Health Checks**: Liveness and readiness probes
- ✅ **Resource Limits**: Proper resource requests and limits
- ✅ **Persistent Storage**: Data preserved across restarts

## 📁 Files Overview

### Core Deployments
- `n8n-deployment-queue-mode.yaml` - Main n8n instance (UI/API)
- `n8n-worker-deployment.yaml` - Worker instances (workflow execution)
- `n8n-runner-deployment.yaml` - Task runner instances (Code node execution)
- `postgres-deployment.yaml` - PostgreSQL database
- `redis-deployment.yaml` - Redis message queue

### Services
- `n8n-service.yaml` - LoadBalancer exposing n8n UI (port 5678)
- `n8n-main-service.yaml` - ClusterIP for main instance
- `postgres-service.yaml` - PostgreSQL service
- `redis-deployment.yaml` - Redis service (included in deployment file)

### Configuration
- `namespace.yaml` - n8n namespace
- `n8n-secret.yaml` - n8n configuration (queue mode, runners, etc.)
- `postgres-secret.yaml` - PostgreSQL credentials
- `postgres-configmap.yaml` - PostgreSQL initialization script

### Storage
- `n8n-claim0-persistentvolumeclaim.yaml` - n8n data storage
- `postgres-claim0-persistentvolumeclaim.yaml` - PostgreSQL data storage
- `redis-claim0-persistentvolumeclaim.yaml` - Redis data storage

### Scripts & Documentation
- `deploy.sh` - Automated deployment script ⭐
- `undeploy.sh` - Automated cleanup script
- `QUICKSTART.md` - Get started in 5 minutes ⭐
- `DEPLOYMENT_GUIDE.md` - Detailed deployment instructions
- `SECRETS_TEMPLATE.md` - How to generate secure secrets

## 🎯 Quick Start

### 1. Generate Secrets
```bash
openssl rand -base64 32  # Encryption key
openssl rand -base64 24  # Runner auth token
openssl rand -base64 24  # Postgres password
```

### 2. Update Secret Files
Edit `postgres-secret.yaml` and `n8n-secret.yaml` with your generated values.

### 3. Deploy
```bash
./deploy.sh
```

### 4. Access n8n
```bash
kubectl get svc n8n -n n8n
# Access at: http://<EXTERNAL-IP>:5678
```

For detailed instructions, see [QUICKSTART.md](QUICKSTART.md).

## 📊 Architecture

```
Internet → Load Balancer → n8n Main → Redis → Workers → Runners → PostgreSQL
```

- **Main Instance**: Handles UI, API, webhooks, and workflow triggers
- **Workers**: Execute workflows from the queue (scale independently)
- **Runners**: Execute Code node scripts in isolated environment
- **Redis**: Message queue for job distribution
- **PostgreSQL**: Persistent data storage

## 🔧 Configuration

### Scaling Workers
```bash
kubectl scale deployment n8n-worker -n n8n --replicas=5
```

### Scaling Runners
```bash
kubectl scale deployment n8n-runner -n n8n --replicas=4
```

### High Availability (Multi-Main)
Add to `n8n-secret.yaml`:
```yaml
N8N_MULTI_MAIN_SETUP_ENABLED: "true"
```

Then scale:
```bash
kubectl scale deployment n8n-main -n n8n --replicas=2
```

## 🔍 Monitoring

```bash
# View logs
kubectl logs -f deployment/n8n-main -n n8n
kubectl logs -f deployment/n8n-worker -n n8n
kubectl logs -f deployment/n8n-runner -n n8n

# Check pod status
kubectl get pods -n n8n

# Check resource usage
kubectl top pods -n n8n
```

## ⚙️ Customization

### Adjust Worker Concurrency
Edit `n8n-worker-deployment.yaml`:
```yaml
args: ["--concurrency=20"]  # Default is 10
```

### Adjust Resource Limits
Edit resource limits in deployment files:
```yaml
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

### Enable Python Runner
Uncomment the Python runner container in `n8n-runner-deployment.yaml`.

## 🗑️ Uninstall

```bash
./undeploy.sh
```

Or manually:
```bash
kubectl delete namespace n8n
```

## 📚 Documentation

- **Quick Start**: [QUICKSTART.md](QUICKSTART.md) - Get started in 5 minutes
- **Full Guide**: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Detailed instructions
- **Secrets**: [SECRETS_TEMPLATE.md](SECRETS_TEMPLATE.md) - Security configuration
- **n8n Docs**: https://docs.n8n.io/hosting/scaling/queue-mode/

## 🆚 Comparison with Basic Deployment

| Feature | Basic (`n8n-deployment.yaml`) | Queue Mode (This Setup) |
|---------|-------------------------------|-------------------------|
| Execution Mode | Single process | Queue-based workers |
| Scalability | Vertical only | Horizontal scaling |
| Workers | None | 3+ worker pods |
| Task Runners | Integrated | Isolated (2+ pods) |
| Redis | Not required | Required |
| HA Support | No | Yes (multi-main) |
| Production Ready | Development | Production ✅ |

## 💡 Why Queue Mode?

**Single Instance Issues:**
- ❌ All executions block the main process
- ❌ Heavy workflows can make UI unresponsive
- ❌ No horizontal scaling
- ❌ Single point of failure

**Queue Mode Benefits:**
- ✅ Workflows executed by dedicated workers
- ✅ UI always responsive
- ✅ Scale workers independently
- ✅ High availability support
- ✅ Better resource utilization
- ✅ Isolated Code execution

## 🎛️ Environment Variables

Key configuration in `n8n-secret.yaml`:

```yaml
# Queue Mode
EXECUTIONS_MODE: "queue"
QUEUE_BULL_REDIS_HOST: "redis-service"

# Task Runners
N8N_RUNNERS_ENABLED: "true"
N8N_RUNNERS_MODE: "external"
N8N_RUNNERS_AUTH_TOKEN: "<secret>"

# Security
N8N_ENCRYPTION_KEY: "<secret>"

# Code Permissions
NODE_FUNCTION_ALLOW_BUILTIN: "crypto,https,http"
N8N_RUNNERS_STDLIB_ALLOW: "json,re,datetime"
```

See [n8n environment variables docs](https://docs.n8n.io/hosting/environment-variables/) for all options.

## 🐛 Troubleshooting

### Workers not picking up jobs
```bash
# Check Redis connection
kubectl exec -it deployment/n8n-worker -n n8n -- nc -zv redis-service 6379

# Verify encryption key matches
kubectl describe secret n8n-secret -n n8n | grep ENCRYPTION_KEY
```

### Runners not connecting
```bash
# Check runner logs
kubectl logs deployment/n8n-runner -n n8n

# Test connection to task broker
kubectl exec -it deployment/n8n-runner -n n8n -- nc -zv n8n-main 5679
```

### Database issues
```bash
# Check PostgreSQL connection
kubectl exec -it deployment/n8n-main -n n8n -- nc -zv postgres-service 5432

# View PostgreSQL logs
kubectl logs deployment/postgres -n n8n
```

## 📈 Resource Requirements

### Minimum (Development/Testing)
- 3 nodes (t3.medium)
- 8 GB RAM total
- 4 vCPUs total

### Recommended (Production)
- 5+ nodes (t3.large or larger)
- 16+ GB RAM total
- 8+ vCPUs total

### Per Component
- **Main**: 640Mi-1280Mi RAM, 200m-1000m CPU
- **Worker**: 1Gi-2Gi RAM, 500m-1000m CPU
- **Runner**: 512Mi-1Gi RAM, 250m-500m CPU
- **PostgreSQL**: 2Gi-4Gi RAM, 1-4 CPUs
- **Redis**: 256Mi-512Mi RAM, 100m-500m CPU

## 🔐 Security Considerations

1. **Generate unique secrets** - Never use default values
2. **Store secrets securely** - Use a password manager
3. **Restrict Code permissions** - Only allow necessary modules
4. **Enable network policies** - Restrict pod-to-pod communication
5. **Use private clusters** - Don't expose to public internet
6. **Enable TLS/HTTPS** - Use cert-manager with Let's Encrypt
7. **Regular backups** - Backup PostgreSQL and persistent volumes

## 🚀 Production Checklist

Before going to production:

- [ ] Generate and store all secrets securely
- [ ] Set up proper domain and DNS
- [ ] Enable HTTPS/TLS
- [ ] Configure PostgreSQL backups
- [ ] Set up monitoring (Prometheus/Grafana)
- [ ] Configure log aggregation
- [ ] Set up alerting
- [ ] Test disaster recovery
- [ ] Document your setup
- [ ] Set up CI/CD for updates
- [ ] Consider using managed services (RDS, ElastiCache)
- [ ] Implement network policies
- [ ] Set up autoscaling (HPA)

## 🆘 Support

- **n8n Community**: https://community.n8n.io/
- **Documentation**: https://docs.n8n.io/
- **GitHub**: https://github.com/n8n-io/n8n

## 📝 License

This deployment configuration is part of the n8n-hosting repository.
See LICENSE file for details.

---

**Ready to deploy?** Start with [QUICKSTART.md](QUICKSTART.md) for a 5-minute deployment!

