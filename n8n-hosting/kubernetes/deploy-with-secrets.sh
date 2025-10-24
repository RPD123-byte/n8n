#!/bin/bash

# Secure deployment script that injects secrets from environment variables
# Never commit actual secrets to git!

set -e

echo "=========================================="
echo "n8n Secure Deployment"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

# Check if we're connected to a cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Not connected to a Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${YELLOW}Current kubectl context:${NC}"
kubectl config current-context
echo ""

# Check for required environment variables
if [ -z "$N8N_ENCRYPTION_KEY" ] || [ -z "$N8N_RUNNERS_AUTH_TOKEN" ] || [ -z "$POSTGRES_PASSWORD" ]; then
    echo -e "${RED}Error: Required environment variables not set${NC}"
    echo ""
    echo "Please set the following environment variables:"
    echo "  export N8N_ENCRYPTION_KEY='your-encryption-key'"
    echo "  export N8N_RUNNERS_AUTH_TOKEN='your-runner-token'"
    echo "  export POSTGRES_PASSWORD='your-postgres-password'"
    echo ""
    echo "Generate new values with:"
    echo "  openssl rand -base64 32  # for N8N_ENCRYPTION_KEY"
    echo "  openssl rand -base64 24  # for N8N_RUNNERS_AUTH_TOKEN"
    echo "  openssl rand -base64 24  # for POSTGRES_PASSWORD"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ All required environment variables are set${NC}"
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
echo "Creating temporary manifests with secrets"
echo "=========================================="

# Create temporary directory for manifests
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Copy manifests to temp directory
cp *.yaml "$TMP_DIR/"

# Inject secrets into temporary manifests
sed -i.bak "s|N8N_ENCRYPTION_KEY: \"PLACEHOLDER_REPLACED_BY_CI\"|N8N_ENCRYPTION_KEY: \"$N8N_ENCRYPTION_KEY\"|g" "$TMP_DIR/n8n-secret.yaml"
sed -i.bak "s|N8N_RUNNERS_AUTH_TOKEN: \"PLACEHOLDER_REPLACED_BY_CI\"|N8N_RUNNERS_AUTH_TOKEN: \"$N8N_RUNNERS_AUTH_TOKEN\"|g" "$TMP_DIR/n8n-secret.yaml"
sed -i.bak "s|POSTGRES_PASSWORD: PLACEHOLDER_REPLACED_BY_CI|POSTGRES_PASSWORD: $POSTGRES_PASSWORD|g" "$TMP_DIR/postgres-secret.yaml"
sed -i.bak "s|POSTGRES_NON_ROOT_PASSWORD: PLACEHOLDER_REPLACED_BY_CI|POSTGRES_NON_ROOT_PASSWORD: $POSTGRES_PASSWORD|g" "$TMP_DIR/postgres-secret.yaml"

# Update image references to use custom images
sed -i.bak "s|image: docker.n8n.io/n8nio/n8n:.*|image: ghcr.io/rpd123-byte/n8n:latest|g" \
  "$TMP_DIR/n8n-deployment-queue-mode.yaml" "$TMP_DIR/n8n-worker-deployment.yaml"

sed -i.bak "s|image: ghcr.io/n8n-io/runners:.*|image: ghcr.io/rpd123-byte/runners:latest|g" \
  "$TMP_DIR/n8n-runner-deployment.yaml"

echo -e "${GREEN}✓ Secrets injected into temporary manifests${NC}"

echo ""
echo "=========================================="
echo "Deploying to Kubernetes"
echo "=========================================="

cd "$TMP_DIR"

# Deploy
kubectl apply -f namespace.yaml
kubectl apply -f postgres-secret.yaml
kubectl apply -f n8n-secret.yaml
kubectl apply -f postgres-claim0-persistentvolumeclaim.yaml
kubectl apply -f n8n-claim0-persistentvolumeclaim.yaml
kubectl apply -f redis-claim0-persistentvolumeclaim.yaml
kubectl apply -f redis-deployment.yaml
kubectl apply -f postgres-configmap.yaml
kubectl apply -f postgres-deployment.yaml
kubectl apply -f postgres-service.yaml

echo ""
echo -e "${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
kubectl wait --for=condition=ready pod -l service=postgres-n8n -n n8n --timeout=300s
echo -e "${GREEN}✓ PostgreSQL is ready${NC}"

echo ""
echo -e "${YELLOW}Waiting for Redis to be ready...${NC}"
kubectl wait --for=condition=ready pod -l service=redis -n n8n --timeout=300s
echo -e "${GREEN}✓ Redis is ready${NC}"

kubectl apply -f n8n-deployment-queue-mode.yaml
kubectl apply -f n8n-service.yaml
kubectl apply -f n8n-main-service.yaml

echo ""
echo -e "${YELLOW}Waiting for n8n main instance to be ready...${NC}"
kubectl wait --for=condition=ready pod -l service=n8n-main -n n8n --timeout=300s
echo -e "${GREEN}✓ n8n main instance is ready${NC}"

kubectl apply -f n8n-worker-deployment.yaml
kubectl apply -f n8n-runner-deployment.yaml

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
echo ""

