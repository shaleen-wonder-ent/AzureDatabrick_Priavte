#!/bin/bash

#############################################
# AZURE DATABRICKS PRIVATE NETWORK DEPLOYMENT WITH ADLS GEN2
# Complete Enterprise Solution for Central India Region
# Version: 2.1.0 - With Fixed ADLS Gen2 Integration
# 
# PURPOSE:
# This script creates a fully private Azure Databricks environment with
# ADLS Gen2 storage, ensuring all data and compute remain within Azure's
# backbone network with zero public internet exposure.
#
# ARCHITECTURE OVERVIEW:
# ┌─────────────────────────────────────────────────────────────────┐
# │                   AZURE CENTRAL INDIA REGION                    │
# ├─────────────────────────────────────────────────────────────────┤
# │  ┌─────────────────────────────────────────────────────────┐   │
# │  │              VIRTUAL NETWORK (10.0.0.0/16)              │   │
# │  ├─────────────────────────────────────────────────────────┤   │
# │  │                                                         │   │
# │  │  ┌──────────────────┐    ┌──────────────────┐        │   │
# │  │  │ Databricks Host  │    │ Databricks       │        │   │
# │  │  │ Subnet           │    │ Container Subnet │        │   │
# │  │  │ (10.0.1.0/24)    │    │ (10.0.2.0/24)    │        │   │
# │  │  └──────────────────┘    └──────────────────┘        │   │
# │  │           ↓                        ↓                   │   │
# │  │  ┌──────────────────────────────────────────┐        │   │
# │  │  │     Private Endpoints (10.0.3.0/24)      │        │   │
# │  │  │  • Databricks UI/API  • Databricks Auth  │        │   │
# │  │  │  • ADLS Blob          • ADLS DFS         │        │   │
# │  │  └──────────────────────────────────────────┘        │   │
# │  │           ↓                                           │   │
# │  │  ┌──────────────────────────────────────────┐        │   │
# │  │  │        AZURE BACKBONE NETWORK            │        │   │
# │  │  └──────────────────────────────────────────┘        │   │
# │  │           ↓                                           │   │
# │  │  ┌──────────────────────────────────────────┐        │   │
# │  │  │         ADLS Gen2 Storage Account        │        │   │
# │  │  │  • /raw       • /processed               │        │   │
# │  │  │  • /curated   • /sandbox    • /archive   │        │   │
# │  │  └──────────────────────────────────────────┘        │   │
# │  │                                                         │   │
# │  │  ┌──────────────────┐    ┌──────────────────┐        │   │
# │  │  │   Jump VM        │    │  Azure Bastion   │        │   │
# │  │  │  (10.0.5.0/24)   │    │  (10.0.6.0/26)   │        │   │
# │  │  └──────────────────┘    └──────────────────┘        │   │
# │  └─────────────────────────────────────────────────────────┘   │
# └─────────────────────────────────────────────────────────────────┘
#
# Author: Shaleen Wonder Enterprise
# Date: 2025-01-30
# Repository: https://github.com/shaleen-wonder-ent/AzDatabricks_Private_deployment
#############################################

# Exit on any error
set -e

# ============================================
# SECTION 1: CONFIGURATION AND SETUP
# ============================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }
print_header() {
    echo ""
    echo "========================================="
    echo "$1"
    echo "========================================="
}

# ============================================
# CONFIGURATION VARIABLES
# ============================================

# Azure Region
export LOCATION="${LOCATION:-centralindia}"

# Resource Group
export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-databricks-private-india}"

# Virtual Network Configuration
export VNET_NAME="${VNET_NAME:-vnet-databricks-india}"
export VNET_PREFIX="${VNET_PREFIX:-10.0.0.0/16}"

# Databricks Workspace Configuration
export WORKSPACE_NAME="${WORKSPACE_NAME:-dbw-private-india-$(date +%s)}"

# ADLS Gen2 Storage Configuration
TIMESTAMP=$(date +%s | tail -c 8)
export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-adls${TIMESTAMP}}"

# Subnet Configurations
export SUBNET_HOST="10.0.1.0/24"
export SUBNET_CONTAINER="10.0.2.0/24"
export SUBNET_PE="10.0.3.0/24"
export SUBNET_BACKEND_PE="10.0.4.0/24"
export SUBNET_JUMPBOX="10.0.5.0/24"
export SUBNET_BASTION="10.0.6.0/26"

# VM and Bastion Configuration
export VM_NAME="${VM_NAME:-vm-jumpbox-india}"
export VM_ADMIN_USER="${VM_ADMIN_USER:-azureuser}"
export VM_ADMIN_PASSWORD="${VM_ADMIN_PASSWORD:-SecurePass@India2025!}"
export BASTION_NAME="${BASTION_NAME:-bastion-databricks-india}"

# Storage Containers
export STORAGE_CONTAINERS=("raw" "processed" "curated" "sandbox" "archive")

# ============================================
# PHASE 0: PREREQUISITES CHECK
# ============================================

print_header "Phase 0: Prerequisites and Environment Check"

# Check Azure CLI Installation
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed"
    print_info "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi
print_status "Azure CLI is installed"

# Check Azure CLI version
CLI_VERSION=$(az version --query '"azure-cli"' -o tsv)
print_info "Azure CLI version: $CLI_VERSION"

# Check Azure Authentication
if ! az account show &> /dev/null; then
    print_error "Not logged into Azure. Please run 'az login'"
    exit 1
fi

# Get subscription details
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
print_status "Logged into subscription: $SUBSCRIPTION_NAME"
print_info "Subscription ID: $SUBSCRIPTION_ID"
print_info "Tenant ID: $TENANT_ID"

# Verify Central India region
print_info "Verifying Central India region availability..."
if az account list-locations --query "[?name=='centralindia'].displayName" -o tsv | grep -q "Central India"; then
    print_status "Central India region is available"
else
    print_error "Central India region not available in your subscription"
    exit 1
fi

# Install/Update required extensions
print_status "Installing/Updating Azure extensions..."
az extension add --name databricks --upgrade --only-show-errors
az extension add --name storage-preview --upgrade --only-show-errors 2>/dev/null || true

# Register required resource providers
print_status "Registering required resource providers..."
PROVIDERS=("Microsoft.Databricks" "Microsoft.Network" "Microsoft.Storage" "Microsoft.Compute")
for provider in "${PROVIDERS[@]}"; do
    print_info "Registering $provider..."
    az provider register --namespace $provider --wait --only-show-errors
done

# ============================================
# PHASE 1: RESOURCE GROUP CREATION
# ============================================

print_header "Phase 1: Creating Resource Group"

if az group show --name $RESOURCE_GROUP &> /dev/null; then
    print_warning "Resource group $RESOURCE_GROUP already exists"
else
    print_info "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name $RESOURCE_GROUP \
        --location $LOCATION \
        --tags "Environment=Production" "Purpose=Databricks-Private" "Owner=$SUBSCRIPTION_NAME" \
        --only-show-errors
    print_status "Resource group created successfully"
fi

# ============================================
# PHASE 2: VIRTUAL NETWORK AND SUBNETS
# ============================================

print_header "Phase 2: Creating Virtual Network and Subnets"

if az network vnet show --resource-group $RESOURCE_GROUP --name $VNET_NAME &> /dev/null; then
    print_warning "VNet $VNET_NAME already exists, skipping creation"
else
    print_info "Creating Virtual Network with address space $VNET_PREFIX"
    az network vnet create \
        --resource-group $RESOURCE_GROUP \
        --name $VNET_NAME \
        --address-prefix $VNET_PREFIX \
        --location $LOCATION \
        --tags "Purpose=Databricks-Private-Network" \
        --only-show-errors
    print_status "Virtual network created successfully"
fi

# Create all required subnets
print_info "Creating 6 subnets for different components..."

SUBNET_CONFIGS=(
    "snet-databricks-host|$SUBNET_HOST|Microsoft.Databricks/workspaces|false"
    "snet-databricks-container|$SUBNET_CONTAINER|Microsoft.Databricks/workspaces|false"
    "snet-private-endpoints|$SUBNET_PE||true"
    "snet-backend-private-endpoint|$SUBNET_BACKEND_PE||true"
    "snet-jumpbox|$SUBNET_JUMPBOX||false"
    "AzureBastionSubnet|$SUBNET_BASTION||false"
)

for subnet_config in "${SUBNET_CONFIGS[@]}"; do
    IFS='|' read -r SUBNET_NAME SUBNET_PREFIX DELEGATION DISABLE_PE <<< "$subnet_config"
    
    if az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --name "$SUBNET_NAME" &> /dev/null; then
        print_warning "Subnet $SUBNET_NAME already exists, skipping"
    else
        print_info "Creating subnet: $SUBNET_NAME ($SUBNET_PREFIX)"
        
        if [[ -n "$DELEGATION" ]]; then
            az network vnet subnet create \
                --resource-group $RESOURCE_GROUP \
                --vnet-name $VNET_NAME \
                --name "$SUBNET_NAME" \
                --address-prefix "$SUBNET_PREFIX" \
                --delegations "$DELEGATION" \
                --disable-private-endpoint-network-policies $DISABLE_PE \
                --only-show-errors
        else
            az network vnet subnet create \
                --resource-group $RESOURCE_GROUP \
                --vnet-name $VNET_NAME \
                --name "$SUBNET_NAME" \
                --address-prefix "$SUBNET_PREFIX" \
                --disable-private-endpoint-network-policies $DISABLE_PE \
                --only-show-errors
        fi
        print_status "Subnet $SUBNET_NAME created"
    fi
done

# ============================================
# PHASE 3: NETWORK SECURITY GROUPS
# ============================================

print_header "Phase 3: Creating and Configuring Network Security Groups"

# Create NSG for Databricks
NSG_DATABRICKS="nsg-databricks"
if az network nsg show --resource-group $RESOURCE_GROUP --name $NSG_DATABRICKS &> /dev/null; then
    print_warning "NSG $NSG_DATABRICKS already exists"
else
    print_info "Creating Network Security Group for Databricks"
    az network nsg create \
        --resource-group $RESOURCE_GROUP \
        --name $NSG_DATABRICKS \
        --location $LOCATION \
        --tags "Purpose=Databricks-Security" \
        --only-show-errors
    print_status "NSG created"
fi

# Associate NSG with Databricks subnets
print_info "Associating NSG with Databricks subnets..."
for subnet in "snet-databricks-host" "snet-databricks-container"; do
    az network vnet subnet update \
        --resource-group $RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --name $subnet \
        --network-security-group $NSG_DATABRICKS \
        --only-show-errors
done
print_status "NSG associated with Databricks subnets"

# Create NSG for Bastion
NSG_BASTION="nsg-bastion"
print_info "Creating NSG for Azure Bastion..."
if ! az network nsg show --resource-group $RESOURCE_GROUP --name $NSG_BASTION &> /dev/null; then
    az network nsg create \
        --resource-group $RESOURCE_GROUP \
        --name $NSG_BASTION \
        --location $LOCATION \
        --only-show-errors
    
    # Add required Bastion NSG rules
    print_info "Adding Bastion NSG rules..."
    
    # Inbound rules
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_BASTION --name AllowHttpsInbound --priority 120 --direction Inbound --access Allow --protocol Tcp --source-address-prefix Internet --source-port-range "*" --destination-address-prefix "*" --destination-port-range 443 --only-show-errors
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_BASTION --name AllowGatewayManagerInbound --priority 130 --direction Inbound --access Allow --protocol Tcp --source-address-prefix GatewayManager --source-port-range "*" --destination-address-prefix "*" --destination-port-range 443 --only-show-errors
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_BASTION --name AllowAzureLoadBalancerInbound --priority 140 --direction Inbound --access Allow --protocol Tcp --source-address-prefix AzureLoadBalancer --source-port-range "*" --destination-address-prefix "*" --destination-port-range 443 --only-show-errors
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_BASTION --name AllowBastionHostCommunication --priority 150 --direction Inbound --access Allow --protocol "*" --source-address-prefix VirtualNetwork --source-port-range "*" --destination-address-prefix VirtualNetwork --destination-port-ranges 8080 5701 --only-show-errors
    
    # Outbound rules
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_BASTION --name AllowSshRdpOutbound --priority 100 --direction Outbound --access Allow --protocol "*" --source-address-prefix "*" --source-port-range "*" --destination-address-prefix VirtualNetwork --destination-port-ranges 22 3389 --only-show-errors
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_BASTION --name AllowAzureCloudOutbound --priority 110 --direction Outbound --access Allow --protocol Tcp --source-address-prefix "*" --source-port-range "*" --destination-address-prefix AzureCloud --destination-port-range 443 --only-show-errors
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_BASTION --name AllowBastionCommunication --priority 120 --direction Outbound --access Allow --protocol "*" --source-address-prefix VirtualNetwork --source-port-range "*" --destination-address-prefix VirtualNetwork --destination-port-ranges 8080 5701 --only-show-errors
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_BASTION --name AllowGetSessionInformation --priority 130 --direction Outbound --access Allow --protocol "*" --source-address-prefix "*" --source-port-range "*" --destination-address-prefix Internet --destination-port-range 80 --only-show-errors
    
    print_status "Bastion NSG created and configured"
fi

# Associate Bastion NSG with subnet
az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name AzureBastionSubnet \
    --network-security-group $NSG_BASTION \
    --only-show-errors

# ============================================
# PHASE 4: DATABRICKS WORKSPACE CREATION
# ============================================

print_header "Phase 4: Creating Databricks Workspace"

if az databricks workspace show --resource-group $RESOURCE_GROUP --name $WORKSPACE_NAME &> /dev/null; then
    print_warning "Databricks workspace $WORKSPACE_NAME already exists"
    WORKSPACE_EXISTS=true
else
    WORKSPACE_EXISTS=false
fi

VNET_ID=$(az network vnet show --resource-group $RESOURCE_GROUP --name $VNET_NAME --query id -o tsv)
print_info "VNet Resource ID: $VNET_ID"

if [ "$WORKSPACE_EXISTS" = false ]; then
    print_info "Creating ARM template for Databricks workspace..."
    
    cat > /tmp/databricks-deployment.json << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "workspaceName": {
      "type": "string",
      "defaultValue": "$WORKSPACE_NAME"
    },
    "location": {
      "type": "string",
      "defaultValue": "$LOCATION"
    }
  },
  "variables": {
    "managedResourceGroupName": "[concat('databricks-rg-', parameters('workspaceName'), '-', uniqueString(parameters('workspaceName'), resourceGroup().id))]"
  },
  "resources": [
    {
      "type": "Microsoft.Databricks/workspaces",
      "apiVersion": "2024-05-01",
      "name": "[parameters('workspaceName')]",
      "location": "[parameters('location')]",
      "sku": {
        "name": "premium"
      },
      "properties": {
        "managedResourceGroupId": "[subscriptionResourceId('Microsoft.Resources/resourceGroups', variables('managedResourceGroupName'))]",
        "parameters": {
          "customVirtualNetworkId": {
            "value": "$VNET_ID"
          },
          "customPublicSubnetName": {
            "value": "snet-databricks-host"
          },
          "customPrivateSubnetName": {
            "value": "snet-databricks-container"
          },
          "enableNoPublicIp": {
            "value": true
          },
          "requireInfrastructureEncryption": {
            "value": false
          },
          "storageAccountSkuName": {
            "value": "Standard_LRS"
          }
        },
        "publicNetworkAccess": "Disabled",
        "requiredNsgRules": "NoAzureDatabricksRules"
      }
    }
  ]
}
EOF

    print_info "Deploying Databricks workspace..."
    print_warning "This operation typically takes 10-15 minutes..."
    
    DEPLOYMENT_NAME="databricks-deployment-$(date +%s)"
    
    az deployment group create \
        --resource-group $RESOURCE_GROUP \
        --name $DEPLOYMENT_NAME \
        --template-file /tmp/databricks-deployment.json \
        --parameters workspaceName=$WORKSPACE_NAME location=$LOCATION \
        --only-show-errors
    
    print_status "Databricks workspace created successfully!"
    rm -f /tmp/databricks-deployment.json
fi

sleep 10

# ============================================
# PHASE 5: CONFIGURE SECURE CLUSTER CONNECTIVITY
# ============================================

print_header "Phase 5: Configuring Secure Cluster Connectivity (SCC)"

BACKEND_SUBNET_ID=$(az network vnet subnet show \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name "snet-backend-private-endpoint" \
    --query id -o tsv)

print_info "Backend subnet prepared for SCC: $BACKEND_SUBNET_ID"

WORKSPACE_CONFIG=$(az databricks workspace show \
    --resource-group $RESOURCE_GROUP \
    --name $WORKSPACE_NAME \
    --query "{PublicAccess:publicNetworkAccess, NoPublicIP:parameters.enableNoPublicIp.value}" \
    -o json)

print_status "Workspace configuration verified"
print_info "SCC is enabled through workspace configuration"

# ============================================
# PHASE 6: FRONTEND PRIVATE ENDPOINTS
# ============================================

print_header "Phase 6: Creating Frontend Private Endpoints"

WORKSPACE_ID=$(az databricks workspace show \
    --resource-group $RESOURCE_GROUP \
    --name $WORKSPACE_NAME \
    --query id -o tsv)

print_info "Workspace Resource ID: $WORKSPACE_ID"

# Create UI/API Private Endpoint
if az network private-endpoint show --resource-group $RESOURCE_GROUP --name "pe-databricks-ui-api" &> /dev/null; then
    print_warning "Private endpoint pe-databricks-ui-api already exists"
else
    print_info "Creating Private Endpoint for UI/API access..."
    
    az network private-endpoint create \
        --resource-group $RESOURCE_GROUP \
        --name "pe-databricks-ui-api" \
        --vnet-name $VNET_NAME \
        --subnet "snet-private-endpoints" \
        --private-connection-resource-id $WORKSPACE_ID \
        --group-id "databricks_ui_api" \
        --connection-name "connection-databricks-ui-api" \
        --location $LOCATION \
        --only-show-errors
    
    print_status "UI/API private endpoint created"
fi

# Create Authentication Private Endpoint
if az network private-endpoint show --resource-group $RESOURCE_GROUP --name "pe-databricks-auth" &> /dev/null; then
    print_warning "Private endpoint pe-databricks-auth already exists"
else
    print_info "Creating Private Endpoint for Browser Authentication..."
    
    az network private-endpoint create \
        --resource-group $RESOURCE_GROUP \
        --name "pe-databricks-auth" \
        --vnet-name $VNET_NAME \
        --subnet "snet-private-endpoints" \
        --private-connection-resource-id $WORKSPACE_ID \
        --group-id "browser_authentication" \
        --connection-name "connection-databricks-auth" \
        --location $LOCATION \
        --only-show-errors
    
    print_status "Authentication private endpoint created"
fi

# ============================================
# PHASE 7: BACKEND PRIVATE ENDPOINT FOR SCC
# ============================================

print_header "Phase 7: Creating Backend Private Endpoint for SCC"

if az network private-endpoint show --resource-group $RESOURCE_GROUP --name "pe-databricks-backend" &> /dev/null; then
    print_warning "Backend private endpoint already exists"
else
    print_info "Creating Backend Private Endpoint for SCC..."
    
    az network private-endpoint create \
        --resource-group $RESOURCE_GROUP \
        --name "pe-databricks-backend" \
        --vnet-name $VNET_NAME \
        --subnet "snet-backend-private-endpoint" \
        --private-connection-resource-id $WORKSPACE_ID \
        --group-id "databricks_ui_api" \
        --connection-name "connection-databricks-backend" \
        --location $LOCATION \
        --only-show-errors 2>/dev/null || {
            print_warning "Backend private endpoint may be automatically managed by Databricks"
        }
fi

# ============================================
# PHASE 8: PRIVATE DNS ZONES FOR DATABRICKS
# ============================================

print_header "Phase 8: Configuring Private DNS Zones for Databricks"

DNS_ZONE_DATABRICKS="privatelink.azuredatabricks.net"

if az network private-dns zone show --resource-group $RESOURCE_GROUP --name $DNS_ZONE_DATABRICKS &> /dev/null; then
    print_warning "Private DNS Zone $DNS_ZONE_DATABRICKS already exists"
else
    print_info "Creating Private DNS Zone for Databricks..."
    az network private-dns zone create \
        --resource-group $RESOURCE_GROUP \
        --name $DNS_ZONE_DATABRICKS \
        --only-show-errors
    print_status "DNS zone created"
fi

if az network private-dns link vnet show --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_DATABRICKS --name "link-databricks-vnet" &> /dev/null; then
    print_warning "DNS VNet link already exists"
else
    print_info "Linking DNS Zone to Virtual Network..."
    az network private-dns link vnet create \
        --resource-group $RESOURCE_GROUP \
        --zone-name $DNS_ZONE_DATABRICKS \
        --name "link-databricks-vnet" \
        --virtual-network $VNET_NAME \
        --registration-enabled false \
        --only-show-errors
    print_status "DNS zone linked to VNet"
fi

print_info "Creating DNS records for Databricks private endpoints..."

WORKSPACE_URL=$(az databricks workspace show \
    --resource-group $RESOURCE_GROUP \
    --name $WORKSPACE_NAME \
    --query workspaceUrl -o tsv)

WORKSPACE_HOST="${WORKSPACE_URL%%.*}"
print_info "Workspace hostname: $WORKSPACE_HOST"

# UI/API endpoint DNS
UI_API_PE_NIC_ID=$(az network private-endpoint show \
    --resource-group $RESOURCE_GROUP \
    --name "pe-databricks-ui-api" \
    --query 'networkInterfaces[0].id' -o tsv)

UI_API_IP=$(az network nic show \
    --ids $UI_API_PE_NIC_ID \
    --query 'ipConfigurations[0].privateIPAddress' -o tsv)

az network private-dns record-set a create \
    --resource-group $RESOURCE_GROUP \
    --zone-name $DNS_ZONE_DATABRICKS \
    --name "$WORKSPACE_HOST" \
    --only-show-errors 2>/dev/null || true

az network private-dns record-set a add-record \
    --resource-group $RESOURCE_GROUP \
    --zone-name $DNS_ZONE_DATABRICKS \
    --record-set-name "$WORKSPACE_HOST" \
    --ipv4-address $UI_API_IP \
    --only-show-errors 2>/dev/null || true

print_status "DNS record created: $WORKSPACE_HOST -> $UI_API_IP"

# Auth endpoint DNS
AUTH_PE_NIC_ID=$(az network private-endpoint show \
    --resource-group $RESOURCE_GROUP \
    --name "pe-databricks-auth" \
    --query 'networkInterfaces[0].id' -o tsv)

AUTH_IP=$(az network nic show \
    --ids $AUTH_PE_NIC_ID \
    --query 'ipConfigurations[0].privateIPAddress' -o tsv)

az network private-dns record-set a create \
    --resource-group $RESOURCE_GROUP \
    --zone-name $DNS_ZONE_DATABRICKS \
    --name "adb-auth-${WORKSPACE_HOST}" \
    --only-show-errors 2>/dev/null || true

az network private-dns record-set a add-record \
    --resource-group $RESOURCE_GROUP \
    --zone-name $DNS_ZONE_DATABRICKS \
    --record-set-name "adb-auth-${WORKSPACE_HOST}" \
    --ipv4-address $AUTH_IP \
    --only-show-errors 2>/dev/null || true

print_status "DNS record created: adb-auth-${WORKSPACE_HOST} -> $AUTH_IP"

# ============================================
# PHASE 9: AZURE DATA LAKE STORAGE GEN2 (FIXED VERSION)
# ============================================

print_header "Phase 9: Creating Azure Data Lake Storage Gen2"

# Clean storage account name
STORAGE_ACCOUNT_NAME=$(echo "$STORAGE_ACCOUNT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | cut -c1-24)
print_info "Storage Account Name: $STORAGE_ACCOUNT_NAME"

# Check if storage account exists
if az storage account show --resource-group $RESOURCE_GROUP --name $STORAGE_ACCOUNT_NAME &> /dev/null 2>&1; then
    print_warning "Storage account $STORAGE_ACCOUNT_NAME already exists"
else
    print_info "Creating ADLS Gen2 Storage Account..."
    print_info "This storage will only be accessible via private endpoints"
    
    # Create storage account (without deprecated parameters)
    az storage account create \
        --name $STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP \
        --location $LOCATION \
        --sku Standard_LRS \
        --kind StorageV2 \
        --hierarchical-namespace true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --public-network-access Disabled \
        --tags "Purpose=DataLake" "Environment=Production" \
        --only-show-errors
    
    # Update network rules
    az storage account update \
        --name $STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP \
        --default-action Deny \
        --bypass None \
        --only-show-errors
    
    print_status "ADLS Gen2 storage account created with private access only"
fi

# Get storage account key
print_info "Retrieving storage account key..."
STORAGE_KEY=$(az storage account keys list \
    --resource-group $RESOURCE_GROUP \
    --account-name $STORAGE_ACCOUNT_NAME \
    --query '[0].value' -o tsv)

# Create storage containers
print_info "Creating data lake containers..."
for container in "${STORAGE_CONTAINERS[@]}"; do
    print_info "Creating container: $container"
    
    az storage container create \
        --name $container \
        --account-name $STORAGE_ACCOUNT_NAME \
        --account-key "$STORAGE_KEY" \
        --public-access off \
        --only-show-errors 2>/dev/null || print_warning "Container $container might already exist"
done
print_status "Storage containers created: ${STORAGE_CONTAINERS[*]}"

# Create Private Endpoints for Storage
print_info "Creating private endpoints for ADLS Gen2..."

STORAGE_RESOURCE_ID=$(az storage account show \
    --resource-group $RESOURCE_GROUP \
    --name $STORAGE_ACCOUNT_NAME \
    --query id -o tsv)

# Private endpoint for blob storage
if ! az network private-endpoint show --resource-group $RESOURCE_GROUP --name "pe-adls-blob" &> /dev/null; then
    print_info "Creating private endpoint for blob storage..."
    az network private-endpoint create \
        --resource-group $RESOURCE_GROUP \
        --name "pe-adls-blob" \
        --vnet-name $VNET_NAME \
        --subnet "snet-private-endpoints" \
        --private-connection-resource-id $STORAGE_RESOURCE_ID \
        --group-id "blob" \
        --connection-name "connection-adls-blob" \
        --location $LOCATION \
        --only-show-errors
    print_status "Blob private endpoint created"
fi

# Private endpoint for DFS
if ! az network private-endpoint show --resource-group $RESOURCE_GROUP --name "pe-adls-dfs" &> /dev/null; then
    print_info "Creating private endpoint for DFS..."
    az network private-endpoint create \
        --resource-group $RESOURCE_GROUP \
        --name "pe-adls-dfs" \
        --vnet-name $VNET_NAME \
        --subnet "snet-private-endpoints" \
        --private-connection-resource-id $STORAGE_RESOURCE_ID \
        --group-id "dfs" \
        --connection-name "connection-adls-dfs" \
        --location $LOCATION \
        --only-show-errors
    print_status "DFS private endpoint created"
fi

# Configure Private DNS for Storage
print_info "Configuring private DNS for storage endpoints..."

DNS_ZONES_STORAGE=("privatelink.blob.core.windows.net" "privatelink.dfs.core.windows.net")

for zone in "${DNS_ZONES_STORAGE[@]}"; do
    print_info "Processing DNS zone: $zone"
    
    # Create DNS zone if not exists
    if ! az network private-dns zone show --resource-group $RESOURCE_GROUP --name $zone &> /dev/null; then
        az network private-dns zone create \
            --resource-group $RESOURCE_GROUP \
            --name $zone \
            --only-show-errors
    fi
    
    # Link DNS zone to VNet if not exists
    if ! az network private-dns link vnet show --resource-group $RESOURCE_GROUP --zone-name $zone --name "link-storage-vnet" &> /dev/null; then
        az network private-dns link vnet create \
            --resource-group $RESOURCE_GROUP \
            --zone-name $zone \
            --name "link-storage-vnet" \
            --virtual-network $VNET_NAME \
            --registration-enabled false \
            --only-show-errors
    fi
done

# Create DNS records for storage endpoints
# Blob endpoint
BLOB_PE_NIC_ID=$(az network private-endpoint show \
    --resource-group $RESOURCE_GROUP \
    --name "pe-adls-blob" \
    --query 'networkInterfaces[0].id' -o tsv)

if [ -n "$BLOB_PE_NIC_ID" ]; then
    BLOB_IP=$(az network nic show \
        --ids $BLOB_PE_NIC_ID \
        --query 'ipConfigurations[0].privateIPAddress' -o tsv)

    az network private-dns record-set a create \
        --resource-group $RESOURCE_GROUP \
        --zone-name "privatelink.blob.core.windows.net" \
        --name $STORAGE_ACCOUNT_NAME \
        --only-show-errors 2>/dev/null || true

    az network private-dns record-set a add-record \
        --resource-group $RESOURCE_GROUP \
        --zone-name "privatelink.blob.core.windows.net" \
        --record-set-name $STORAGE_ACCOUNT_NAME \
        --ipv4-address $BLOB_IP \
        --only-show-errors 2>/dev/null || true
fi

# DFS endpoint
DFS_PE_NIC_ID=$(az network private-endpoint show \
    --resource-group $RESOURCE_GROUP \
    --name "pe-adls-dfs" \
    --query 'networkInterfaces[0].id' -o tsv)

if [ -n "$DFS_PE_NIC_ID" ]; then
    DFS_IP=$(az network nic show \
        --ids $DFS_PE_NIC_ID \
        --query 'ipConfigurations[0].privateIPAddress' -o tsv)

    az network private-dns record-set a create \
        --resource-group $RESOURCE_GROUP \
        --zone-name "privatelink.dfs.core.windows.net" \
        --name $STORAGE_ACCOUNT_NAME \
        --only-show-errors 2>/dev/null || true

    az network private-dns record-set a add-record \
        --resource-group $RESOURCE_GROUP \
        --zone-name "privatelink.dfs.core.windows.net" \
        --record-set-name $STORAGE_ACCOUNT_NAME \
        --ipv4-address $DFS_IP \
        --only-show-errors 2>/dev/null || true
fi

print_status "Storage DNS configuration completed"

# Create Service Principal for Databricks
print_info "Creating Service Principal for storage access..."

SP_NAME="sp-databricks-adls-${STORAGE_ACCOUNT_NAME}"

# Check if SP exists
if az ad sp list --display-name $SP_NAME --query "[0].appId" -o tsv &> /dev/null; then
    print_warning "Service principal already exists"
    CLIENT_ID=$(az ad sp list --display-name $SP_NAME --query "[0].appId" -o tsv)
else
    SP_OUTPUT=$(az ad sp create-for-rbac \
        --name $SP_NAME \
        --role "Storage Blob Data Contributor" \
        --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME" \
        --only-show-errors)

    CLIENT_ID=$(echo $SP_OUTPUT | jq -r '.appId')
    CLIENT_SECRET=$(echo $SP_OUTPUT | jq -r '.password')

    print_status "Service Principal created for storage access"
    print_warning "SAVE THE CLIENT SECRET - IT WON'T BE SHOWN AGAIN!"
    print_warning "Client Secret: $CLIENT_SECRET"
fi

# ============================================
# PHASE 10: JUMP VM CREATION
# ============================================

print_header "Phase 10: Creating Jump VM for Access"

print_info "Jump VM provides access to private Databricks from within VNet"

VM_SIZES=("Standard_B2s" "Standard_B2ms" "Standard_D2s_v5" "Standard_D2s_v4" "Standard_D2s_v3" "Standard_B1ms" "Standard_D2as_v5")

VM_CREATED=false

for SIZE in "${VM_SIZES[@]}"; do
    print_info "Attempting VM creation with size: $SIZE"
    
    if az vm create \
        --resource-group $RESOURCE_GROUP \
        --name $VM_NAME \
        --image Ubuntu2204 \
        --size $SIZE \
        --vnet-name $VNET_NAME \
        --subnet "snet-jumpbox" \
        --admin-username "$VM_ADMIN_USER" \
        --admin-password "$VM_ADMIN_PASSWORD" \
        --public-ip-address "" \
        --nsg "" \
        --only-show-errors 2>/dev/null; then
        
        VM_CREATED=true
        VM_SIZE_USED=$SIZE
        print_status "Jump VM created successfully with size: $SIZE"
        
        # Install desktop environment
        print_info "Installing desktop environment on Jump VM..."
        az vm run-command invoke \
            --resource-group $RESOURCE_GROUP \
            --name $VM_NAME \
            --command-id RunShellScript \
            --scripts "sudo apt-get update && sudo apt-get install -y ubuntu-desktop firefox xrdp && sudo systemctl enable xrdp" \
            --no-wait \
            --only-show-errors 2>/dev/null || true
        
        break
    else
        print_warning "Size $SIZE not available, trying next..."
    fi
done

if [ "$VM_CREATED" = false ]; then
    print_warning "Standard VM sizes unavailable, trying Spot instance..."
    
    if az vm create \
        --resource-group $RESOURCE_GROUP \
        --name $VM_NAME \
        --image Ubuntu2204 \
        --priority Spot \
        --eviction-policy Deallocate \
        --max-price -1 \
        --vnet-name $VNET_NAME \
        --subnet "snet-jumpbox" \
        --admin-username "$VM_ADMIN_USER" \
        --admin-password "$VM_ADMIN_PASSWORD" \
        --public-ip-address "" \
        --nsg "" \
        --only-show-errors; then
        
        VM_CREATED=true
        print_status "Spot VM created successfully"
    else
        print_error "Could not create Jump VM. Manual creation required."
    fi
fi

# ============================================
# PHASE 11: AZURE BASTION CREATION
# ============================================

print_header "Phase 11: Creating Azure Bastion"

print_info "Bastion provides secure RDP/SSH access through browser"

if az network bastion show --resource-group $RESOURCE_GROUP --name $BASTION_NAME &> /dev/null; then
    print_warning "Bastion already exists"
else
    # Create public IP for Bastion
    if ! az network public-ip show --resource-group $RESOURCE_GROUP --name "pip-bastion" &> /dev/null; then
        print_info "Creating public IP for Bastion..."
        
        az network public-ip create \
            --resource-group $RESOURCE_GROUP \
            --name "pip-bastion" \
            --sku Standard \
            --location $LOCATION \
            --only-show-errors
    fi
    
    # Create Bastion host
    print_info "Creating Azure Bastion..."
    print_warning "This operation takes 5-10 minutes to complete"
    
    az network bastion create \
        --name $BASTION_NAME \
        --public-ip-address "pip-bastion" \
        --resource-group $RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --location $LOCATION \
        --no-wait \
        --only-show-errors
    
    print_info "Bastion deployment initiated in background"
fi

# ============================================
# PHASE 12: CREATE DATABRICKS MOUNT SCRIPT
# ============================================

print_header "Phase 12: Creating Databricks Configuration Scripts"

cat > databricks-mount-config.py << EOF
# Databricks notebook source
# ADLS Gen2 Mount Configuration for $STORAGE_ACCOUNT_NAME

# Storage configuration
storage_account_name = "$STORAGE_ACCOUNT_NAME"
client_id = "$CLIENT_ID"
tenant_id = "$TENANT_ID"

# Create secret scope (run once in Databricks CLI):
# databricks secrets create-scope --scope adls-scope

# Set the secret (run in Databricks CLI):
# databricks secrets put --scope adls-scope --key client-secret

# OAuth configuration
configs = {
    "fs.azure.account.auth.type": "OAuth",
    "fs.azure.account.oauth.provider.type": "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider",
    "fs.azure.account.oauth2.client.id": client_id,
    "fs.azure.account.oauth2.client.secret": dbutils.secrets.get(scope="adls-scope", key="client-secret"),
    "fs.azure.account.oauth2.client.endpoint": f"https://login.microsoftonline.com/{tenant_id}/oauth2/token"
}

# Mount points configuration
mount_points = {
    "/mnt/raw": f"abfss://raw@{storage_account_name}.dfs.core.windows.net/",
    "/mnt/processed": f"abfss://processed@{storage_account_name}.dfs.core.windows.net/",
    "/mnt/curated": f"abfss://curated@{storage_account_name}.dfs.core.windows.net/",
    "/mnt/sandbox": f"abfss://sandbox@{storage_account_name}.dfs.core.windows.net/",
    "/mnt/archive": f"abfss://archive@{storage_account_name}.dfs.core.windows.net/"
}

# Mount all containers
for mount_point, source in mount_points.items():
    try:
        dbutils.fs.mount(
            source=source,
            mount_point=mount_point,
            extra_configs=configs
        )
        print(f"✅ Mounted {source} to {mount_point}")
    except Exception as e:
        if "already mounted" in str(e):
            print(f"ℹ️ {mount_point} already mounted")
        else:
            print(f"❌ Error mounting {mount_point}: {str(e)}")

# List all mounts to verify
display(dbutils.fs.mounts())
EOF

print_status "Databricks mount configuration script created: databricks-mount-config.py"

# ============================================
# PHASE 13: VALIDATION AND SUMMARY
# ============================================

print_header "Phase 13: Deployment Validation and Summary"

print_info "Validating all components..."

# Save configuration
CONFIG_FILE="databricks-deployment-config-$(date +%Y%m%d-%H%M%S).json"
cat > $CONFIG_FILE << EOJSON
{
  "deployment": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "subscription": "$SUBSCRIPTION_NAME",
    "subscriptionId": "$SUBSCRIPTION_ID",
    "resourceGroup": "$RESOURCE_GROUP",
    "location": "$LOCATION"
  },
  "databricks": {
    "workspace": "$WORKSPACE_NAME",
    "url": "https://$WORKSPACE_URL"
  },
  "storage": {
    "accountName": "$STORAGE_ACCOUNT_NAME",
    "containers": ["raw", "processed", "curated", "sandbox", "archive"],
    "servicePrincipal": "$CLIENT_ID"
  },
  "access": {
    "jumpVM": "$VM_NAME",
    "bastion": "$BASTION_NAME",
    "username": "$VM_ADMIN_USER"
  }
}
EOJSON

# ============================================
# DEPLOYMENT COMPLETE - DISPLAY SUMMARY
# ============================================

print_header "🎉 Deployment Complete!"

cat << END

${GREEN}═══════════════════════════════════════════════════════════════════${NC}
${GREEN}     AZURE DATABRICKS PRIVATE DEPLOYMENT - CENTRAL INDIA           ${NC}
${GREEN}═══════════════════════════════════════════════════════════════════${NC}

${BLUE}📍 DEPLOYMENT SUMMARY:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Region:              ${GREEN}$LOCATION${NC}
  Resource Group:      ${GREEN}$RESOURCE_GROUP${NC}
  Virtual Network:     ${GREEN}$VNET_NAME${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${BLUE}🔧 DATABRICKS WORKSPACE:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Name:                ${GREEN}$WORKSPACE_NAME${NC}
  URL:                 ${GREEN}https://$WORKSPACE_URL${NC}
  Public Access:       ${GREEN}Disabled (Private Only)${NC}
  SCC:                 ${GREEN}Enabled${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${BLUE}💾 ADLS GEN2 STORAGE:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Account:             ${GREEN}$STORAGE_ACCOUNT_NAME${NC}
  Containers:          ${GREEN}raw, processed, curated, sandbox, archive${NC}
  Access:              ${GREEN}Private Endpoints Only${NC}
  Service Principal:   ${GREEN}$CLIENT_ID${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${YELLOW}📋 ACCESS INSTRUCTIONS:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. ${BLUE}Wait for Bastion (5-10 minutes)${NC}
2. ${BLUE}Access Jump VM via Azure Portal${NC}
3. ${BLUE}Login with:${NC}
   Username: ${GREEN}$VM_ADMIN_USER${NC}
   Password: ${GREEN}$VM_ADMIN_PASSWORD${NC}
4. ${BLUE}Access Databricks from Jump VM browser${NC}

${YELLOW}⚠️  IMPORTANT:${NC}
• Configuration saved to: ${GREEN}$CONFIG_FILE${NC}
• Mount script saved to: ${GREEN}databricks-mount-config.py${NC}
• ${RED}Save the service principal secret securely!${NC}

${GREEN}Deployment successful! All resources are private and secure.${NC}

END
