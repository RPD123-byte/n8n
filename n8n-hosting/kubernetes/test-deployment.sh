#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}    n8n Kubernetes Deployment Test Script${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Step 1: Verify cluster connection
echo -e "${YELLOW}🔍 Step 1: Verifying cluster connection...${NC}"
echo -e "Current context: ${GREEN}$(kubectl config current-context)${NC}"
echo -e "Cluster info:"
kubectl cluster-info | head -2
echo ""

# Step 2: Check storage classes
echo -e "${YELLOW}💾 Step 2: Checking storage classes...${NC}"
kubectl get storageclass
echo ""

if ! kubectl get storageclass gp3 &> /dev/null; then
    echo -e "${RED}❌ gp3 storage class not found!${NC}"
    echo -e "${YELLOW}Creating gp3 storage class...${NC}"
    cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
    echo -e "${GREEN}✅ gp3 storage class created${NC}"
else
    echo -e "${GREEN}✅ gp3 storage class exists${NC}"
fi
echo ""

# Step 3: Check/create namespace
echo -e "${YELLOW}📦 Step 3: Checking namespace...${NC}"
if kubectl get namespace n8n &> /dev/null; then
    echo -e "${YELLOW}⚠️  Namespace 'n8n' already exists. Delete it? (y/n)${NC}"
    read -r CONFIRM
    if [[ $CONFIRM =~ ^[Yy]$ ]]; then
        kubectl delete namespace n8n
        kubectl wait --for=delete namespace/n8n --timeout=120s || true
        echo -e "${GREEN}✅ Namespace deleted${NC}"
    else
        echo -e "${YELLOW}⏭️  Keeping existing namespace${NC}"
    fi
fi
echo ""

# Step 4: Create namespace and secrets
echo -e "${YELLOW}🔐 Step 4: Creating namespace and secrets...${NC}"
kubectl apply -f namespace.yaml
kubectl apply -f postgres-secret.yaml
kubectl apply -f n8n-secret.yaml
echo -e "${GREEN}✅ Namespace and secrets created${NC}"
echo ""

# Step 5: Test PVC creation and binding
echo -e "${YELLOW}💿 Step 5: Testing PVC creation...${NC}"
echo "Creating PVCs..."
kubectl apply -f postgres-claim0-persistentvolumeclaim.yaml
kubectl apply -f n8n-claim0-persistentvolumeclaim.yaml
kubectl apply -f redis-claim0-persistentvolumeclaim.yaml

echo ""
echo -e "${YELLOW}⏳ Waiting for PVCs to bind (this may take 30-60 seconds)...${NC}"
echo "PVC Status:"
kubectl get pvc -n n8n

echo ""
echo -e "${YELLOW}Watching PVCs (press Ctrl+C once all are Bound)...${NC}"
kubectl get pvc -n n8n -w &
WATCH_PID=$!

# Wait for PVCs to bind (with timeout)
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    PENDING=$(kubectl get pvc -n n8n -o json | jq -r '.items[] | select(.status.phase != "Bound") | .metadata.name' | wc -l)
    if [ "$PENDING" -eq 0 ]; then
        kill $WATCH_PID 2>/dev/null || true
        echo ""
        echo -e "${GREEN}✅ All PVCs are bound!${NC}"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    kill $WATCH_PID 2>/dev/null || true
    echo ""
    echo -e "${RED}❌ PVCs failed to bind within ${TIMEOUT}s${NC}"
    echo ""
    echo -e "${YELLOW}Debugging info:${NC}"
    kubectl get pvc -n n8n
    echo ""
    kubectl describe pvc -n n8n
    echo ""
    echo -e "${RED}Deployment test failed. Fix the PVC issues above.${NC}"
    exit 1
fi

echo ""
kubectl get pvc -n n8n
echo ""

# Step 6: Deploy PostgreSQL
echo -e "${YELLOW}🐘 Step 6: Deploying PostgreSQL...${NC}"
kubectl apply -f postgres-configmap.yaml
kubectl apply -f postgres-deployment.yaml
kubectl apply -f postgres-service.yaml

echo -e "${YELLOW}⏳ Waiting for PostgreSQL to be ready...${NC}"
kubectl wait --for=condition=ready pod -l service=postgres-n8n -n n8n --timeout=300s || {
    echo -e "${RED}❌ PostgreSQL failed to start${NC}"
    kubectl get pods -n n8n
    kubectl describe pod -l service=postgres-n8n -n n8n
    kubectl logs -l service=postgres-n8n -n n8n --tail=50
    exit 1
}
echo -e "${GREEN}✅ PostgreSQL is ready${NC}"
echo ""

# Step 7: Deploy Redis
echo -e "${YELLOW}📮 Step 7: Deploying Redis...${NC}"
kubectl apply -f redis-deployment.yaml

echo -e "${YELLOW}⏳ Waiting for Redis to be ready...${NC}"
kubectl wait --for=condition=ready pod -l service=redis -n n8n --timeout=180s || {
    echo -e "${RED}❌ Redis failed to start${NC}"
    kubectl get pods -n n8n
    exit 1
}
echo -e "${GREEN}✅ Redis is ready${NC}"
echo ""

# Step 8: Deploy n8n
echo -e "${YELLOW}🚀 Step 8: Deploying n8n...${NC}"
kubectl apply -f n8n-deployment-queue-mode.yaml
kubectl apply -f n8n-service.yaml
kubectl apply -f n8n-main-service.yaml

echo -e "${YELLOW}⏳ Waiting for n8n-main to be ready...${NC}"
echo "This may take 2-3 minutes..."
kubectl wait --for=condition=ready pod -l service=n8n-main -n n8n --timeout=600s || {
    echo -e "${RED}❌ n8n-main failed to start${NC}"
    kubectl get pods -n n8n
    kubectl describe pod -l service=n8n-main -n n8n
    kubectl logs -l service=n8n-main -n n8n --tail=100 --all-containers=true
    exit 1
}
echo -e "${GREEN}✅ n8n-main is ready${NC}"
echo ""

# Step 9: Deploy workers and runners
echo -e "${YELLOW}⚙️  Step 9: Deploying workers and runners...${NC}"
kubectl apply -f n8n-worker-deployment.yaml
kubectl apply -f n8n-runner-deployment.yaml

echo -e "${YELLOW}⏳ Waiting for workers and runners...${NC}"
sleep 30

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 Deployment Test Complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📊 Current Status:${NC}"
kubectl get pods -n n8n
echo ""
kubectl get svc -n n8n
echo ""
echo -e "${YELLOW}💡 To access n8n:${NC}"
echo "  kubectl port-forward -n n8n svc/n8n 5678:5678"
echo "  Then open: http://localhost:5678"
echo ""
echo -e "${YELLOW}🔍 To check logs:${NC}"
echo "  kubectl logs -n n8n -l service=n8n-main -f"
echo ""
echo -e "${YELLOW}🗑️  To clean up:${NC}"
echo "  kubectl delete namespace n8n"
echo ""

