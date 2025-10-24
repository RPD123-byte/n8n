#!/bin/bash

# n8n Queue Mode Deployment Script
# This script deploys n8n with PostgreSQL, Redis, workers, and task runners to Kubernetes

set -e  # Exit on error

echo "=========================================="
echo "n8n Queue Mode Deployment"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo "Install it with: brew install kubectl"
    exit 1
fi

# Check if we're connected to a cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Not connected to a Kubernetes cluster${NC}"
    echo "Please configure kubectl to connect to your cluster first"
    exit 1
fi

echo -e "${YELLOW}Current kubectl context:${NC}"
kubectl config current-context
echo ""

# Verify secrets have been updated
echo -e "${YELLOW}Checking if secrets have been configured...${NC}"
if grep -q "CHANGE_ME" n8n-secret.yaml; then
    echo -e "${RED}Error: n8n-secret.yaml contains placeholder values${NC}"
    echo ""
    echo "Please update n8n-secret.yaml with actual values:"
    echo "  1. Generate encryption key: openssl rand -base64 32"
    echo "  2. Generate runner auth token: openssl rand -base64 24"
    echo "  3. Replace 'CHANGE_ME' values in n8n-secret.yaml"
    echo ""
    exit 1
fi

if grep -q "changePassword" postgres-secret.yaml; then
    echo -e "${RED}Error: postgres-secret.yaml contains placeholder values${NC}"
    echo ""
    echo "Please update postgres-secret.yaml with actual values:"
    echo "  1. Generate password: openssl rand -base64 24"
    echo "  2. Replace 'changePassword' values in postgres-secret.yaml"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Secrets appear to be configured${NC}"
echo ""

# Confirm deployment
read -p "Deploy n8n to cluster '$(kubectl config current-context)'? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "=========================================="
echo "Step 1: Creating namespace"
echo "=========================================="
kubectl apply -f namespace.yaml

echo ""
echo "=========================================="
echo "Step 2: Creating secrets"
echo "=========================================="
kubectl apply -f postgres-secret.yaml
kubectl apply -f n8n-secret.yaml

echo ""
echo "=========================================="
echo "Step 3: Creating persistent volume claims"
echo "=========================================="
kubectl apply -f postgres-claim0-persistentvolumeclaim.yaml
kubectl apply -f n8n-claim0-persistentvolumeclaim.yaml
kubectl apply -f redis-claim0-persistentvolumeclaim.yaml

echo ""
echo "=========================================="
echo "Step 4: Deploying Redis and PostgreSQL"
echo "=========================================="
kubectl apply -f redis-deployment.yaml
kubectl apply -f postgres-configmap.yaml
kubectl apply -f postgres-deployment.yaml
kubectl apply -f postgres-service.yaml

echo ""
echo -e "${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
kubectl wait --for=condition=ready pod -l service=postgres-n8n -n n8n --timeout=300s || {
    echo -e "${RED}Error: PostgreSQL failed to start${NC}"
    echo "Check logs with: kubectl logs -l service=postgres-n8n -n n8n"
    exit 1
}
echo -e "${GREEN}✓ PostgreSQL is ready${NC}"

echo ""
echo -e "${YELLOW}Waiting for Redis to be ready...${NC}"
kubectl wait --for=condition=ready pod -l service=redis -n n8n --timeout=300s || {
    echo -e "${RED}Error: Redis failed to start${NC}"
    echo "Check logs with: kubectl logs -l service=redis -n n8n"
    exit 1
}
echo -e "${GREEN}✓ Redis is ready${NC}"

echo ""
echo "=========================================="
echo "Step 5: Deploying n8n main instance"
echo "=========================================="
kubectl apply -f n8n-deployment-queue-mode.yaml
kubectl apply -f n8n-service.yaml
kubectl apply -f n8n-main-service.yaml

echo ""
echo -e "${YELLOW}Waiting for n8n main instance to be ready...${NC}"
kubectl wait --for=condition=ready pod -l service=n8n-main -n n8n --timeout=300s || {
    echo -e "${RED}Error: n8n main instance failed to start${NC}"
    echo "Check logs with: kubectl logs -l service=n8n-main -n n8n"
    exit 1
}
echo -e "${GREEN}✓ n8n main instance is ready${NC}"

echo ""
echo "=========================================="
echo "Step 6: Deploying workers and runners"
echo "=========================================="
kubectl apply -f n8n-worker-deployment.yaml
kubectl apply -f n8n-runner-deployment.yaml

echo ""
echo -e "${YELLOW}Waiting for workers to be ready...${NC}"
kubectl wait --for=condition=ready pod -l service=n8n-worker -n n8n --timeout=300s || {
    echo -e "${YELLOW}Warning: Workers may still be starting up${NC}"
}

echo ""
echo -e "${YELLOW}Waiting for runners to be ready...${NC}"
kubectl wait --for=condition=ready pod -l service=n8n-runner -n n8n --timeout=300s || {
    echo -e "${YELLOW}Warning: Runners may still be starting up${NC}"
}

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""

# Show pod status
echo -e "${GREEN}Pod Status:${NC}"
kubectl get pods -n n8n
echo ""

# Get load balancer URL
echo -e "${YELLOW}Getting load balancer URL...${NC}"
echo "This may take a few minutes for AWS to provision the load balancer"
echo ""

for i in {1..30}; do
    EXTERNAL_IP=$(kubectl get svc n8n -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$EXTERNAL_IP" ]; then
        echo -e "${GREEN}✓ Load balancer is ready!${NC}"
        echo ""
        echo "=========================================="
        echo "Access n8n at:"
        echo -e "${GREEN}http://$EXTERNAL_IP:5678${NC}"
        echo "=========================================="
        echo ""
        break
    fi
    echo "Waiting for load balancer... ($i/30)"
    sleep 10
done

if [ -z "$EXTERNAL_IP" ]; then
    echo -e "${YELLOW}Load balancer not ready yet. Check status with:${NC}"
    echo "kubectl get svc n8n -n n8n"
fi

echo ""
echo "Useful commands:"
echo "  View all resources:     kubectl get all -n n8n"
echo "  Check logs (main):      kubectl logs -f deployment/n8n-main -n n8n"
echo "  Check logs (workers):   kubectl logs -f deployment/n8n-worker -n n8n"
echo "  Check logs (runners):   kubectl logs -f deployment/n8n-runner -n n8n"
echo "  Scale workers:          kubectl scale deployment n8n-worker -n n8n --replicas=5"
echo "  Scale runners:          kubectl scale deployment n8n-runner -n n8n --replicas=3"
echo ""
echo "For detailed documentation, see DEPLOYMENT_GUIDE.md"

