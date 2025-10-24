# 🚀 Start Here: n8n Queue Mode Deployment

Welcome! This directory contains everything you need to deploy n8n in production-ready queue mode on Kubernetes.

## ⚡ Quick Deploy (5 minutes)

### 1. **Generate Secrets**
```bash
# Run this one-liner to generate all required secrets
echo "=== Copy these values ==="
echo "For postgres-secret.yaml:"
echo "  POSTGRES_PASSWORD: $(openssl rand -base64 24)"
echo ""
echo "For n8n-secret.yaml:"
echo "  N8N_ENCRYPTION_KEY: $(openssl rand -base64 32)"
echo "  N8N_RUNNERS_AUTH_TOKEN: $(openssl rand -base64 24)"
```

### 2. **Update Secret Files**
```bash
# Edit these two files with values from step 1
vi postgres-secret.yaml  # Replace changePassword
vi n8n-secret.yaml       # Replace CHANGE_ME values
```

### 3. **Deploy**
```bash
./deploy.sh
```

### 4. **Verify**
```bash
./verify.sh
```

### 5. **Access n8n**
```bash
kubectl get svc n8n -n n8n
# Access at: http://<EXTERNAL-IP>:5678
```

**Done!** 🎉

---

## 📚 Documentation

Choose your path:

### 🏃 **Just Want to Deploy Fast?**
→ Read: [QUICKSTART.md](QUICKSTART.md) (5-minute guide)

### 📖 **Want Detailed Instructions?**
→ Read: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) (Complete guide)

### 🔐 **Need Help with Secrets?**
→ Read: [SECRETS_TEMPLATE.md](SECRETS_TEMPLATE.md) (Security setup)

### 🤔 **Want to Understand Everything?**
→ Read: [README_QUEUE_MODE.md](README_QUEUE_MODE.md) (Full explanation)

---

## 📁 What's in This Directory?

### 🎯 **Start Here**
- `00_START_HERE.md` ← You are here
- `QUICKSTART.md` - 5-minute deployment guide
- `DEPLOYMENT_GUIDE.md` - Detailed instructions
- `README_QUEUE_MODE.md` - Complete reference

### 🔧 **Scripts** (Automated)
- `deploy.sh` ⭐ - Deploy everything automatically
- `undeploy.sh` - Remove everything
- `verify.sh` - Verify deployment health

### 📦 **Kubernetes Manifests**

**Core n8n Components:**
- `n8n-deployment-queue-mode.yaml` - Main instance (UI/API)
- `n8n-worker-deployment.yaml` - Workers (3 replicas)
- `n8n-runner-deployment.yaml` - Task runners (2 replicas)
- `n8n-service.yaml` - LoadBalancer service
- `n8n-main-service.yaml` - Internal service
- `n8n-claim0-persistentvolumeclaim.yaml` - Storage

**Dependencies:**
- `redis-deployment.yaml` - Message queue + service
- `redis-claim0-persistentvolumeclaim.yaml` - Redis storage
- `postgres-deployment.yaml` - Database
- `postgres-service.yaml` - Database service
- `postgres-claim0-persistentvolumeclaim.yaml` - Database storage
- `postgres-configmap.yaml` - Database init script

**Configuration:**
- `namespace.yaml` - n8n namespace
- `n8n-secret.yaml` ⚠️ - Queue mode config (EDIT THIS)
- `postgres-secret.yaml` ⚠️ - Database credentials (EDIT THIS)

### 📖 **Legacy Files** (Basic Deployment)
- `n8n-deployment.yaml` - Old single-instance deployment (don't use)

---

## 🏗️ What You're Deploying

```
┌─────────────────────────────────────────────┐
│           AWS Load Balancer                 │
│         (Public HTTP access)                │
└──────────────┬──────────────────────────────┘
               │
               ↓
┌──────────────────────────────────────────────┐
│        n8n Main Instance (1 pod)             │
│  • Serves UI at port 5678                    │
│  • Handles webhooks and triggers             │
│  • Pushes jobs to Redis queue                │
└──────────┬───────────────────────────────────┘
           │
           ↓
┌──────────────────────────────────────────────┐
│          Redis (Message Queue)               │
│  • Manages job queue                         │
│  • Coordinates worker tasks                  │
└──────────┬───────────────────────────────────┘
           │
           ↓
┌──────────────────────────────────────────────┐
│       n8n Workers (3 pods)                   │
│  • Pick up jobs from Redis                   │
│  • Execute workflow nodes                    │
│  • Scale horizontally (add more pods)        │
└──────────┬───────────────────────────────────┘
           │
           ↓
┌──────────────────────────────────────────────┐
│       n8n Task Runners (2 pods)              │
│  • Execute Code node scripts                 │
│  • Isolated sandboxed environment            │
│  • Supports JavaScript & Python              │
└──────────┬───────────────────────────────────┘
           │
           ↓
┌──────────────────────────────────────────────┐
│          PostgreSQL Database                 │
│  • Stores workflows                          │
│  • Stores executions                         │
│  • Stores encrypted credentials              │
└──────────────────────────────────────────────┘
```

**Total: 7 pods** (can scale to 20+)

---

## ✅ What You Get

- ✅ **Queue Mode**: Workflows executed by dedicated workers
- ✅ **Horizontal Scaling**: Add more workers as needed
- ✅ **Task Runners**: Isolated Code node execution
- ✅ **PostgreSQL**: Production database (not SQLite)
- ✅ **Redis**: Message queue for job distribution
- ✅ **High Availability**: Can run multiple main instances
- ✅ **Health Checks**: Automatic pod restart on failure
- ✅ **Resource Limits**: Prevents resource exhaustion
- ✅ **Persistent Storage**: Data survives pod restarts

---

## 🎛️ Common Operations

### View Status
```bash
kubectl get pods -n n8n
```

### View Logs
```bash
kubectl logs -f deployment/n8n-main -n n8n     # Main instance
kubectl logs -f deployment/n8n-worker -n n8n   # Workers
kubectl logs -f deployment/n8n-runner -n n8n   # Runners
```

### Scale Workers
```bash
kubectl scale deployment n8n-worker -n n8n --replicas=5
```

### Scale Runners
```bash
kubectl scale deployment n8n-runner -n n8n --replicas=4
```

### Restart Component
```bash
kubectl rollout restart deployment/n8n-worker -n n8n
```

### Check Resources
```bash
kubectl top pods -n n8n
```

### Get Access URL
```bash
kubectl get svc n8n -n n8n
```

---

## 🆚 Why Not Use Basic Deployment?

The existing `n8n-deployment.yaml` in this repo is a **basic single-instance setup**:

| Feature | Basic | Queue Mode (This) |
|---------|-------|-------------------|
| Execution | Single process | Dedicated workers |
| Scaling | Vertical only | Horizontal ✅ |
| UI Performance | Blocks during execution | Always responsive ✅ |
| HA Support | No | Yes ✅ |
| Task Runners | Integrated | Isolated ✅ |
| Production Ready | Testing only | Production ✅ |

**Use queue mode for:**
- Production deployments
- Multiple concurrent workflows
- Heavy/long-running workflows
- High availability requirements
- Scaling beyond single instance

---

## ⚠️ Important: Before You Deploy

### 1. **Generate Unique Secrets**
Never use default passwords! Generate secure random values.

### 2. **Save Secrets Securely**
Store encryption keys in a password manager. You'll need them for:
- Adding more workers
- Disaster recovery
- Migrating clusters

### 3. **Understand Encryption Key**
The `N8N_ENCRYPTION_KEY` encrypts stored credentials. If you lose it:
- ❌ Cannot decrypt existing credentials
- ❌ Must recreate all connections
- ❌ Data loss!

**Save it securely!**

---

## 🚀 Next Steps After Deployment

1. ✅ Deploy with `./deploy.sh`
2. ✅ Verify with `./verify.sh`
3. ✅ Access UI and create admin account
4. ✅ Create test workflow
5. ✅ Monitor logs to see queue in action
6. 🎯 Set up your own domain
7. 🎯 Enable HTTPS/TLS
8. 🎯 Configure PostgreSQL backups
9. 🎯 Set up monitoring (Prometheus/Grafana)
10. 🎯 Configure autoscaling

---

## 🆘 Troubleshooting

### Deployment fails?
```bash
# Check what's wrong
kubectl get pods -n n8n
kubectl describe pod <pod-name> -n n8n
kubectl logs <pod-name> -n n8n
```

### Workers not executing?
```bash
# Verify Redis connection
kubectl exec -it deployment/n8n-worker -n n8n -- nc -zv redis-service 6379

# Check encryption key matches
kubectl describe secret n8n-secret -n n8n
```

### Can't access UI?
```bash
# Check load balancer status
kubectl get svc n8n -n n8n

# May take 2-5 minutes for AWS to provision
```

### Still stuck?
1. Read [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Troubleshooting section
2. Run `./verify.sh` to diagnose issues
3. Check logs: `kubectl logs -f deployment/n8n-main -n n8n`
4. Ask in [n8n Community Forum](https://community.n8n.io/)

---

## 💰 Cost Estimate (AWS)

**Minimum setup (~$150-200/month):**
- EKS Control Plane: ~$75/month
- 3× t3.medium nodes: ~$100/month
- Load Balancer: ~$20/month
- EBS Storage: ~$10/month

**Production setup (~$400-600/month):**
- EKS Control Plane: ~$75/month
- 5× t3.large nodes: ~$350/month
- Load Balancer: ~$20/month
- RDS PostgreSQL: ~$50/month (instead of pod)
- ElastiCache Redis: ~$50/month (instead of pod)
- Storage & backups: ~$30/month

**Optimize costs:**
- Use spot instances for workers
- Use reserved instances for main/db
- Right-size resource limits
- Enable cluster autoscaling

---

## 📞 Support

- **Community Forum**: https://community.n8n.io/
- **Documentation**: https://docs.n8n.io/
- **GitHub Issues**: https://github.com/n8n-io/n8n/issues

---

## 🎓 Learning Resources

- [n8n Queue Mode Docs](https://docs.n8n.io/hosting/scaling/queue-mode/)
- [Environment Variables](https://docs.n8n.io/hosting/environment-variables/)
- [Task Runners](https://docs.n8n.io/hosting/configuration/task-runners/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)

---

## ✨ Ready to Deploy?

**Three simple steps:**

1. Generate secrets (see top of this file)
2. Run `./deploy.sh`
3. Access n8n and start building workflows!

**Questions?** Start with [QUICKSTART.md](QUICKSTART.md)

**Good luck! 🚀**

