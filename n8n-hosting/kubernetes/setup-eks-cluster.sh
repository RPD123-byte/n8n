#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}    n8n EKS Cluster Setup Script${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if required tools are installed
echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"
for cmd in aws eksctl kubectl; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}❌ $cmd is not installed. Please install it first.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ $cmd is installed${NC}"
done

# Get configuration
read -p "Enter AWS region (default: us-west-2): " AWS_REGION
AWS_REGION=${AWS_REGION:-us-west-2}

read -p "Enter EKS cluster name (default: n8n): " CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-n8n}

read -p "Enter node instance type (default: t3.medium): " INSTANCE_TYPE
INSTANCE_TYPE=${INSTANCE_TYPE:-t3.medium}

read -p "Enter number of nodes (default: 3): " NODE_COUNT
NODE_COUNT=${NODE_COUNT:-3}

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}📋 Configuration Summary:${NC}"
echo -e "  Region:        ${GREEN}$AWS_REGION${NC}"
echo -e "  Cluster Name:  ${GREEN}$CLUSTER_NAME${NC}"
echo -e "  Instance Type: ${GREEN}$INSTANCE_TYPE${NC}"
echo -e "  Node Count:    ${GREEN}$NODE_COUNT${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p "Continue with these settings? (y/n): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}⚠️  Setup cancelled.${NC}"
    exit 0
fi

# Check if cluster already exists
echo ""
echo -e "${YELLOW}🔍 Checking if cluster already exists...${NC}"
if eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
    echo -e "${GREEN}✅ Cluster '$CLUSTER_NAME' already exists. Skipping cluster creation.${NC}"
    SKIP_CLUSTER_CREATE=true
else
    echo -e "${YELLOW}📦 Cluster does not exist. Will create it.${NC}"
    SKIP_CLUSTER_CREATE=false
fi

# Step 1: Create EKS cluster (if needed)
if [ "$SKIP_CLUSTER_CREATE" = false ]; then
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🚀 Step 1: Creating EKS Cluster${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    eksctl create cluster \
        --name $CLUSTER_NAME \
        --region $AWS_REGION \
        --nodegroup-name n8n-nodes \
        --node-type $INSTANCE_TYPE \
        --nodes $NODE_COUNT \
        --nodes-min 2 \
        --nodes-max 5 \
        --managed \
        --with-oidc
    
    echo -e "${GREEN}✅ Cluster created successfully!${NC}"
else
    echo -e "${YELLOW}⏭️  Skipping cluster creation.${NC}"
    
    # Update kubeconfig
    echo -e "${YELLOW}🔧 Updating kubeconfig...${NC}"
    aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
fi

# Step 2: Install EBS CSI Driver
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}💾 Step 2: Installing EBS CSI Driver${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check if EBS CSI driver already exists
if eksctl get addon --name aws-ebs-csi-driver --cluster $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
    echo -e "${GREEN}✅ EBS CSI Driver already installed. Skipping.${NC}"
else
    echo -e "${YELLOW}📦 Creating IAM service account for EBS CSI driver...${NC}"
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Create IAM role for EBS CSI driver
    eksctl create iamserviceaccount \
        --name ebs-csi-controller-sa \
        --namespace kube-system \
        --cluster $CLUSTER_NAME \
        --region $AWS_REGION \
        --role-name "AmazonEKS_EBS_CSI_DriverRole_$CLUSTER_NAME" \
        --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
        --approve \
        --override-existing-serviceaccounts
    
    echo -e "${YELLOW}📦 Installing EBS CSI driver addon...${NC}"
    
    # Install the EBS CSI driver
    eksctl create addon \
        --name aws-ebs-csi-driver \
        --cluster $CLUSTER_NAME \
        --region $AWS_REGION \
        --service-account-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole_$CLUSTER_NAME \
        --force
    
    echo -e "${GREEN}✅ EBS CSI Driver installed!${NC}"
fi

# Step 3: Verify storage class
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}💿 Step 3: Verifying Storage Classes${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "${YELLOW}⏳ Waiting for EBS CSI driver to be ready...${NC}"
sleep 30

echo -e "${YELLOW}📋 Available storage classes:${NC}"
kubectl get storageclass

# Always create gp3 storage class (idempotent)
echo -e "${YELLOW}📦 Creating gp3 storage class...${NC}"
cat <<EOF | kubectl apply -f -
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

if kubectl get storageclass gp3 &> /dev/null; then
    echo -e "${GREEN}✅ gp3 storage class is available!${NC}"
else
    echo -e "${RED}❌ Failed to create gp3 storage class!${NC}"
    exit 1
fi

# Step 4: Save cluster info
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}💾 Step 4: Saving Cluster Information${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Create a file with cluster info
cat > cluster-info.txt <<EOF
EKS Cluster Information
======================
Cluster Name: $CLUSTER_NAME
Region: $AWS_REGION
Instance Type: $INSTANCE_TYPE
Node Count: $NODE_COUNT

GitHub Secrets to Set:
=====================
AWS_REGION=$AWS_REGION
EKS_CLUSTER_NAME=$CLUSTER_NAME

To set these secrets, run:
echo "$AWS_REGION" | gh secret set AWS_REGION
echo "$CLUSTER_NAME" | gh secret set EKS_CLUSTER_NAME

Cluster Endpoints:
==================
EOF

kubectl cluster-info >> cluster-info.txt

echo -e "${GREEN}✅ Cluster info saved to cluster-info.txt${NC}"

# Summary
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 Setup Complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo ""
echo -e "1. ${GREEN}Set GitHub Secrets:${NC}"
echo -e "   cd /path/to/your/repo"
echo -e "   echo \"$AWS_REGION\" | gh secret set AWS_REGION"
echo -e "   echo \"$CLUSTER_NAME\" | gh secret set EKS_CLUSTER_NAME"
echo ""
echo -e "2. ${GREEN}Generate and set n8n secrets:${NC}"
echo -e "   openssl rand -hex 32 | gh secret set N8N_ENCRYPTION_KEY"
echo -e "   openssl rand -hex 32 | gh secret set N8N_RUNNERS_AUTH_TOKEN"
echo -e "   openssl rand -base64 32 | gh secret set POSTGRES_PASSWORD"
echo ""
echo -e "3. ${GREEN}Push to master to trigger deployment:${NC}"
echo -e "   git push origin master"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Your EKS cluster is ready for n8n deployment!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

