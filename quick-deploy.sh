#!/bin/bash

#############################################
# Quick Azure Deployment using ARM Template
# Alternative to the full bash script for Cloud Shell users
#############################################

# Set parameters
RESOURCE_GROUP="rg-databricks-private-india"
LOCATION="centralindia"
DEPLOYMENT_NAME="databricks-adls-deployment-$(date +%s)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Azure Databricks + ADLS Gen2 Quick Deployment${NC}"
echo "================================================="

# Check if logged in
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Please login to Azure first:${NC}"
    echo "az login"
    exit 1
fi

# Get subscription info
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo -e "${GREEN}✓${NC} Using subscription: $SUBSCRIPTION_NAME"

# Create resource group
echo -e "${BLUE}Creating resource group...${NC}"
az group create --name $RESOURCE_GROUP --location $LOCATION

# Get admin password
echo -e "${YELLOW}Enter password for Jump VM admin user:${NC}"
read -s VM_PASSWORD

# Deploy ARM template
echo -e "${BLUE}Deploying infrastructure (this may take 15-20 minutes)...${NC}"
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --name $DEPLOYMENT_NAME \
    --template-file azure-deploy.json \
    --parameters vmAdminPassword=$VM_PASSWORD

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Complete the private endpoints setup using the main script"
    echo "2. Configure service principal for ADLS Gen2 access"
    echo "3. Set up Azure Bastion for secure access"
    echo ""
    echo "Or run the full script for complete setup:"
    echo "./scripts/setup-databricks-centralindia-complete-documented.sh"
else
    echo -e "${YELLOW}⚠️ Deployment encountered issues. Check the error messages above.${NC}"
fi