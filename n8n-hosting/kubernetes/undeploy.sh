#!/bin/bash

# n8n Undeployment Script
# This script removes all n8n resources from Kubernetes

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "n8n Undeployment"
echo "=========================================="
echo ""

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

echo -e "${YELLOW}Current kubectl context:${NC}"
kubectl config current-context
echo ""

echo -e "${RED}WARNING: This will DELETE all n8n resources including:${NC}"
echo "  - All workflows and executions"
echo "  - PostgreSQL database and data"
echo "  - Redis cache"
echo "  - All persistent volumes and data"
echo ""

read -p "Are you sure you want to continue? (yes/NO) " -r
echo ""
if [[ ! $REPLY == "yes" ]]; then
    echo "Undeployment cancelled"
    exit 0
fi

echo ""
echo "Deleting n8n resources..."

# Delete in reverse order
kubectl delete -f n8n-runner-deployment.yaml --ignore-not-found=true
kubectl delete -f n8n-worker-deployment.yaml --ignore-not-found=true
kubectl delete -f n8n-main-service.yaml --ignore-not-found=true
kubectl delete -f n8n-service.yaml --ignore-not-found=true
kubectl delete -f n8n-deployment-queue-mode.yaml --ignore-not-found=true
kubectl delete -f postgres-service.yaml --ignore-not-found=true
kubectl delete -f postgres-deployment.yaml --ignore-not-found=true
kubectl delete -f postgres-configmap.yaml --ignore-not-found=true
kubectl delete -f redis-deployment.yaml --ignore-not-found=true

# Wait a moment for pods to terminate
echo "Waiting for pods to terminate..."
sleep 5

# Delete PVCs (this will delete data!)
echo ""
read -p "Delete persistent volumes and ALL DATA? (yes/NO) " -r
echo ""
if [[ $REPLY == "yes" ]]; then
    kubectl delete -f redis-claim0-persistentvolumeclaim.yaml --ignore-not-found=true
    kubectl delete -f n8n-claim0-persistentvolumeclaim.yaml --ignore-not-found=true
    kubectl delete -f postgres-claim0-persistentvolumeclaim.yaml --ignore-not-found=true
    echo "Persistent volumes deleted"
else
    echo "Keeping persistent volumes (data preserved)"
fi

# Delete secrets
kubectl delete -f n8n-secret.yaml --ignore-not-found=true
kubectl delete -f postgres-secret.yaml --ignore-not-found=true

# Optionally delete namespace
echo ""
read -p "Delete entire n8n namespace? (yes/NO) " -r
echo ""
if [[ $REPLY == "yes" ]]; then
    kubectl delete namespace n8n --ignore-not-found=true
    echo "Namespace deleted"
else
    echo "Keeping namespace"
fi

echo ""
echo "=========================================="
echo "Undeployment complete"
echo "=========================================="

