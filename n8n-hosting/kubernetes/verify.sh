#!/bin/bash

# n8n Deployment Verification Script
# This script verifies that all components are working correctly

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "n8n Deployment Verification"
echo "=========================================="
echo ""

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl is installed${NC}"

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}✗ Not connected to a cluster${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Connected to cluster: $(kubectl config current-context)${NC}"

echo ""
echo "Checking namespace..."
if kubectl get namespace n8n &> /dev/null; then
    echo -e "${GREEN}✓ Namespace 'n8n' exists${NC}"
else
    echo -e "${RED}✗ Namespace 'n8n' not found${NC}"
    echo "Run ./deploy.sh to deploy"
    exit 1
fi

echo ""
echo "=========================================="
echo "Pod Status"
echo "=========================================="

# Function to check pod status
check_pod() {
    local label=$1
    local name=$2
    local expected=$3
    
    local count=$(kubectl get pods -n n8n -l "$label" --no-headers 2>/dev/null | wc -l)
    local ready=$(kubectl get pods -n n8n -l "$label" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [ "$ready" -eq "$expected" ]; then
        echo -e "${GREEN}✓ $name: $ready/$expected running${NC}"
        return 0
    elif [ "$ready" -gt 0 ]; then
        echo -e "${YELLOW}⚠ $name: $ready/$expected running${NC}"
        return 1
    else
        echo -e "${RED}✗ $name: 0/$expected running${NC}"
        return 1
    fi
}

check_pod "service=postgres-n8n" "PostgreSQL" 1
check_pod "service=redis" "Redis" 1
check_pod "service=n8n-main" "n8n Main" 1
check_pod "service=n8n-worker" "n8n Workers" 3
check_pod "service=n8n-runner" "n8n Runners" 2

echo ""
echo "=========================================="
echo "Service Status"
echo "=========================================="

# Check services
if kubectl get svc postgres-service -n n8n &> /dev/null; then
    echo -e "${GREEN}✓ PostgreSQL service exists${NC}"
else
    echo -e "${RED}✗ PostgreSQL service not found${NC}"
fi

if kubectl get svc redis-service -n n8n &> /dev/null; then
    echo -e "${GREEN}✓ Redis service exists${NC}"
else
    echo -e "${RED}✗ Redis service not found${NC}"
fi

if kubectl get svc n8n -n n8n &> /dev/null; then
    echo -e "${GREEN}✓ n8n LoadBalancer service exists${NC}"
    EXTERNAL_IP=$(kubectl get svc n8n -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$EXTERNAL_IP" ]; then
        echo -e "${GREEN}  Load Balancer URL: http://$EXTERNAL_IP:5678${NC}"
    else
        echo -e "${YELLOW}  Load Balancer: Pending (may take a few minutes)${NC}"
    fi
else
    echo -e "${RED}✗ n8n service not found${NC}"
fi

echo ""
echo "=========================================="
echo "Connectivity Tests"
echo "=========================================="

# Test Redis connectivity from worker
echo "Testing Redis connectivity from worker..."
if kubectl get pods -n n8n -l service=n8n-worker --no-headers 2>/dev/null | head -1 | grep -q Running; then
    WORKER_POD=$(kubectl get pods -n n8n -l service=n8n-worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if kubectl exec -n n8n "$WORKER_POD" -- nc -zv redis-service 6379 &> /dev/null; then
        echo -e "${GREEN}✓ Workers can connect to Redis${NC}"
    else
        echo -e "${RED}✗ Workers cannot connect to Redis${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No worker pods running to test${NC}"
fi

# Test PostgreSQL connectivity from main
echo "Testing PostgreSQL connectivity from main..."
if kubectl get pods -n n8n -l service=n8n-main --no-headers 2>/dev/null | head -1 | grep -q Running; then
    MAIN_POD=$(kubectl get pods -n n8n -l service=n8n-main -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if kubectl exec -n n8n "$MAIN_POD" -- nc -zv postgres-service 5432 &> /dev/null; then
        echo -e "${GREEN}✓ Main instance can connect to PostgreSQL${NC}"
    else
        echo -e "${RED}✗ Main instance cannot connect to PostgreSQL${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No main pod running to test${NC}"
fi

# Test task broker connectivity from runner
echo "Testing task broker connectivity from runner..."
if kubectl get pods -n n8n -l service=n8n-runner --no-headers 2>/dev/null | head -1 | grep -q Running; then
    RUNNER_POD=$(kubectl get pods -n n8n -l service=n8n-runner -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if kubectl exec -n n8n "$RUNNER_POD" -c n8n-runner-javascript -- nc -zv n8n-main 5679 &> /dev/null; then
        echo -e "${GREEN}✓ Runners can connect to task broker${NC}"
    else
        echo -e "${RED}✗ Runners cannot connect to task broker${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No runner pods running to test${NC}"
fi

echo ""
echo "=========================================="
echo "Health Checks"
echo "=========================================="

# Check main instance health
if kubectl get pods -n n8n -l service=n8n-main --no-headers 2>/dev/null | head -1 | grep -q Running; then
    MAIN_POD=$(kubectl get pods -n n8n -l service=n8n-main -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if kubectl exec -n n8n "$MAIN_POD" -- curl -s http://localhost:5678/healthz &> /dev/null; then
        echo -e "${GREEN}✓ Main instance health check passed${NC}"
    else
        echo -e "${RED}✗ Main instance health check failed${NC}"
    fi
fi

# Check worker health
if kubectl get pods -n n8n -l service=n8n-worker --no-headers 2>/dev/null | head -1 | grep -q Running; then
    WORKER_POD=$(kubectl get pods -n n8n -l service=n8n-worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if kubectl exec -n n8n "$WORKER_POD" -- curl -s http://localhost:5678/healthz &> /dev/null; then
        echo -e "${GREEN}✓ Worker health check passed${NC}"
    else
        echo -e "${RED}✗ Worker health check failed${NC}"
    fi
fi

echo ""
echo "=========================================="
echo "Resource Usage"
echo "=========================================="

if command -v kubectl &> /dev/null && kubectl top nodes &> /dev/null 2>&1; then
    echo "Pod resource usage:"
    kubectl top pods -n n8n 2>/dev/null || echo -e "${YELLOW}Metrics server not available${NC}"
else
    echo -e "${YELLOW}Metrics server not available - cannot show resource usage${NC}"
fi

echo ""
echo "=========================================="
echo "Recent Logs (Last 5 lines)"
echo "=========================================="

if kubectl get pods -n n8n -l service=n8n-main --no-headers 2>/dev/null | head -1 | grep -q Running; then
    echo ""
    echo -e "${YELLOW}Main instance:${NC}"
    kubectl logs -n n8n -l service=n8n-main --tail=5 2>/dev/null || echo "No logs available"
fi

if kubectl get pods -n n8n -l service=n8n-worker --no-headers 2>/dev/null | head -1 | grep -q Running; then
    echo ""
    echo -e "${YELLOW}Workers:${NC}"
    kubectl logs -n n8n -l service=n8n-worker --tail=5 2>/dev/null || echo "No logs available"
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="

TOTAL_PODS=$(kubectl get pods -n n8n --no-headers 2>/dev/null | wc -l)
RUNNING_PODS=$(kubectl get pods -n n8n --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

echo "Total pods: $TOTAL_PODS"
echo "Running pods: $RUNNING_PODS"

if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All systems operational!${NC}"
    
    if [ -n "$EXTERNAL_IP" ]; then
        echo ""
        echo "Access n8n at: http://$EXTERNAL_IP:5678"
    else
        echo ""
        echo "Get access URL with: kubectl get svc n8n -n n8n"
    fi
else
    echo ""
    echo -e "${YELLOW}⚠ Some pods are not running${NC}"
    echo "Check detailed status with: kubectl get pods -n n8n"
    echo "Check logs with: kubectl logs -f deployment/<name> -n n8n"
fi

echo ""
echo "Useful commands:"
echo "  kubectl get pods -n n8n"
echo "  kubectl logs -f deployment/n8n-main -n n8n"
echo "  kubectl logs -f deployment/n8n-worker -n n8n"
echo "  kubectl logs -f deployment/n8n-runner -n n8n"
echo "  kubectl top pods -n n8n"

