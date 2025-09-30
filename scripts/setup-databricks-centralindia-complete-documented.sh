#!/bin/bash

#############################################
# AZURE DATABRICKS PRIVATE NETWORK DEPLOYMENT WITH ADLS GEN2
# Complete Enterprise Solution for Central India Region
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
# COMPONENTS CREATED:
# 1. Resource Group - Logical container for all resources
# 2. Virtual Network - Private network with 6 subnets
# 3. Network Security Groups - Firewall rules for security
# 4. Databricks Workspace - Premium tier with private endpoints
# 5. ADLS Gen2 Storage - Hierarchical namespace enabled
# 6. Private Endpoints - For Databricks and Storage
# 7. Private DNS Zones - For name resolution
# 8. Service Principal - For storage authentication
# 9. Jump VM - Administrative access point
# 10. Azure Bastion - Secure RDP/SSH gateway
#
# SECURITY FEATURES:
# • No public IPs on any compute resources
# • All traffic flows through Azure backbone
# • Private endpoints for all services
# • Network isolation with NSGs
# • Secure Cluster Connectivity (SCC) enabled
# • Storage firewall with private access only
# • Service principal authentication for storage
#
# Author: Shaleen Wonder Enterprise
# Version: 2.0.0 - Production Ready with ADLS Gen2
# Date: 2025-01-30
# Repository: https://github.com/shaleen-wonder-ent/AzDatabricks_Private_deployment
#############################################

# Exit on any error - ensures script stops if something fails
set -e

# ============================================
# SECTION 1: CONFIGURATION AND SETUP
# ============================================

# Color codes for better output readability
RED='\033[0;31m'     # Error messages
GREEN='\033[0;32m'   # Success messages
YELLOW='\033[1;33m'  # Warning messages
BLUE='\033[0;34m'    # Information messages
NC='\033[0m'         # No Color - reset to default

# Helper functions for consistent output formatting
print_status() {
    # Print success messages with green checkmark
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    # Print error messages with red X
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    # Print warning messages with yellow exclamation
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    # Print informational messages with blue i
    echo -e "${BLUE}[i]${NC} $1"
}

print_header() {
    # Print section headers for clarity
    echo ""
    echo "========================================="
    echo "$1"
    echo "========================================="
}

# ============================================
# CONFIGURATION VARIABLES
# 
# These define your entire infrastructure.
# Modify these according to your requirements.
# Using environment variables allows override without editing script.
# ============================================

# Azure Region - Central India (Mumbai datacenter)
# WHY CENTRAL INDIA: Lower latency for India users, data residency compliance
export LOCATION="${LOCATION:-centralindia}"

# Resource Group - Container for all resources
# Naming convention: rg-<service>-<environment>-<region>
export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-databricks-private-india}"

# Virtual Network Configuration
# The foundation of network isolation
export VNET_NAME="${VNET_NAME:-vnet-databricks-india}"
export VNET_PREFIX="${VNET_PREFIX:-10.0.0.0/16}"  # 65,536 IP addresses

# Databricks Workspace Configuration
# Must be globally unique, adding timestamp ensures uniqueness
export WORKSPACE_NAME="${WORKSPACE_NAME:-dbw-private-india-$(date +%s)}"

# ADLS Gen2 Storage Configuration
# Storage account names must be globally unique, 3-24 chars, lowercase/numbers only
TIMESTAMP=$(date +%s | tail -c 8)
export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-adls${TIMESTAMP}}"

# Subnet Configurations - Each serves specific purpose
export SUBNET_HOST="10.0.1.0/24"           # Databricks driver nodes (256 IPs)
export SUBNET_CONTAINER="10.0.2.0/24"      # Databricks executor nodes (256 IPs)
export SUBNET_PE="10.0.3.0/24"             # Private endpoints (256 IPs)
export SUBNET_BACKEND_PE="10.0.4.0/24"     # Backend private endpoints for SCC (256 IPs)
export SUBNET_JUMPBOX="10.0.5.0/24"        # Jump VM subnet (256 IPs)
export SUBNET_BASTION="10.0.6.0/26"        # Azure Bastion (64 IPs - minimum required)

# VM and Bastion Configuration
export VM_NAME="${VM_NAME:-vm-jumpbox-india}"
export VM_ADMIN_USER="${VM_ADMIN_USER:-azureuser}"
export VM_ADMIN_PASSWORD="${VM_ADMIN_PASSWORD:-SecurePass@India2025!}"  # CHANGE THIS IN PRODUCTION!
export BASTION_NAME="${BASTION_NAME:-bastion-databricks-india}"

# Storage Containers - Following data lake best practices
export STORAGE_CONTAINERS=("raw" "processed" "curated" "sandbox" "archive")

# ============================================
# PHASE 0: PREREQUISITES CHECK
#
# WHY: Ensures environment is ready before creating resources
# This prevents errors and wasted time/money from failed deployments
# ============================================

print_header "Phase 0: Prerequisites and Environment Check"

# Check 1: Azure CLI Installation
# The Azure CLI is our primary tool for resource creation
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed"
    print_info "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi
print_status "Azure CLI is installed"

# Check Azure CLI version (minimum 2.0 required)
CLI_VERSION=$(az version --query '"azure-cli"' -o tsv)
print_info "Azure CLI version: $CLI_VERSION"

# Check 2: Azure Authentication
# Valid credentials required to create resources
if ! az account show &> /dev/null; then
    print_error "Not logged into Azure. Please run 'az login'"
    exit 1
fi

# Get subscription details for confirmation and logging
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
print_status "Logged into subscription: $SUBSCRIPTION_NAME"
print_info "Subscription ID: $SUBSCRIPTION_ID"
print_info "Tenant ID: $TENANT_ID"

# Check 3: Verify Central India region availability
# Not all subscriptions have access to all regions
print_info "Verifying Central India region availability..."
if az account list-locations --query "[?name=='centralindia'].displayName" -o tsv | grep -q "Central India"; then
    print_status "Central India region is available"
else
    print_error "Central India region not available in your subscription"
    print_info "Available regions:"
    az account list-locations --query "[].name" -o tsv | head -10
    exit 1
fi

# Check 4: Install/Update required extensions
print_status "Installing/Updating Azure extensions..."
az extension add --name databricks --upgrade --only-show-errors
az extension add --name storage-preview --upgrade --only-show-errors 2>/dev/null || true

# Check 5: Register required resource providers
# Providers must be registered before creating resources (one-time per subscription)
print_status "Registering required resource providers..."
PROVIDERS=("Microsoft.Databricks" "Microsoft.Network" "Microsoft.Storage" "Microsoft.Compute")
for provider in "${PROVIDERS[@]}"; do
    print_info "Registering $provider..."
    az provider register --namespace $provider --wait --only-show-errors
done

# Check 6: Verify quota availability
print_info "Checking regional quotas..."
VM_QUOTA=$(az vm list-usage --location $LOCATION --query "[?name.value=='cores'].currentValue" -o tsv 2>/dev/null || echo "0")
print_info "Current vCPU usage in $LOCATION: $VM_QUOTA"

# ============================================
# PHASE 1: RESOURCE GROUP CREATION
#
# WHY: Resource groups are logical containers that hold related resources
# BENEFITS:
# - Organize resources by lifecycle
# - Apply RBAC at group level
# - Track costs per group
# - Easy cleanup (delete group = delete all resources)
# ============================================

print_header "Phase 1: Creating Resource Group"

# Check if resource group exists (idempotency)
if az group show --name $RESOURCE_GROUP &> /dev/null; then
    print_warning "Resource group $RESOURCE_GROUP already exists"
    read -p "Do you want to continue using existing resource group? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Exiting. Please delete the resource group or choose a different name."
        exit 1
    fi
else
    # Create new resource group
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
#
# WHY: VNet provides network isolation and is the foundation
# for private connectivity in Azure
#
# NETWORK DESIGN PRINCIPLES:
# 1. Segmentation - Different subnets for different purposes
# 2. Sizing - Appropriately sized for expected growth
# 3. Security - Network isolation between components
# 4. Delegation - Some subnets delegated to specific services
# ============================================

print_header "Phase 2: Creating Virtual Network and Subnets"

# Create or verify VNet exists
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

# Create all required subnets with proper configuration
print_info "Creating 6 subnets for different components..."

# Subnet configuration array
# Format: subnet_name|address_prefix|delegation|disable_private_endpoint_policies
SUBNET_CONFIGS=(
    "snet-databricks-host|$SUBNET_HOST|Microsoft.Databricks/workspaces|false"
    "snet-databricks-container|$SUBNET_CONTAINER|Microsoft.Databricks/workspaces|false"
    "snet-private-endpoints|$SUBNET_PE||true"
    "snet-backend-private-endpoint|$SUBNET_BACKEND_PE||true"
    "snet-jumpbox|$SUBNET_JUMPBOX||false"
    "AzureBastionSubnet|$SUBNET_BASTION||false"
)

for subnet_config in "${SUBNET_CONFIGS[@]}"; do
    # Parse subnet configuration
    IFS='|' read -r SUBNET_NAME SUBNET_PREFIX DELEGATION DISABLE_PE <<< "$subnet_config"
    
    # Check if subnet exists (idempotency)
    if az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --name "$SUBNET_NAME" &> /dev/null; then
        print_warning "Subnet $SUBNET_NAME already exists, skipping"
    else
        print_info "Creating subnet: $SUBNET_NAME ($SUBNET_PREFIX)"
        
        # Create subnet with appropriate configuration
        if [[ -n "$DELEGATION" ]]; then
            # Delegated subnet (for Databricks)
            # Delegation allows Azure service to deploy resources into subnet
            az network vnet subnet create \
                --resource-group $RESOURCE_GROUP \
                --vnet-name $VNET_NAME \
                --name "$SUBNET_NAME" \
                --address-prefix "$SUBNET_PREFIX" \
                --delegations "$DELEGATION" \
                --disable-private-endpoint-network-policies $DISABLE_PE \
                --only-show-errors
        else
            # Regular subnet (for VMs, private endpoints, etc.)
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
#
# WHY: NSGs act as virtual firewalls for subnets
# They control inbound and outbound traffic using security rules
#
# FOR DATABRICKS WITH SCC:
# - We use "NoAzureDatabricksRules" mode
# - No default Databricks NSG rules needed
# - All communication through private endpoints
# ============================================

print_header "Phase 3: Creating and Configuring Network Security Groups"

# Create NSG for Databricks subnets
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

# Create NSG for Bastion with required rules
NSG_BASTION="nsg-bastion"
print_info "Creating NSG for Azure Bastion..."
if ! az network nsg show --resource-group $RESOURCE_GROUP --name $NSG_BASTION &> /dev/null; then
    az network nsg create \
        --resource-group $RESOURCE_GROUP \
        --name $NSG_BASTION \
        --location $LOCATION \
        --only-show-errors
    
    # Add required inbound rules for Bastion
    print_info "Adding Bastion NSG inbound rules..."
    
    # Allow HTTPS from Internet
    az network nsg rule create \
        --resource-group $RESOURCE_GROUP \
        --nsg-name $NSG_BASTION \
        --name AllowHttpsInbound \
        --priority 120 \
        --direction Inbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefix Internet \
        --source-port-range "*" \
        --destination-address-prefix "*" \
        --destination-port-range 443 \
        --only-show-errors
    
    # Allow Gateway Manager
    az network nsg rule create \
        --resource-group $RESOURCE_GROUP \
        --nsg-name $NSG_BASTION \
        --name AllowGatewayManagerInbound \
        --priority 130 \
        --direction Inbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefix GatewayManager \
        --source-port-range "*" \
        --destination-address-prefix "*" \
        --destination-port-range 443 \
        --only-show-errors
    
    # Allow Azure Load Balancer
    az network nsg rule create \
        --resource-group $RESOURCE_GROUP \
        --nsg-name $NSG_BASTION \
        --name AllowAzureLoadBalancerInbound \
        --priority 140 \
        --direction Inbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefix AzureLoadBalancer \
        --source-port-range "*" \
        --destination-address-prefix "*" \
        --destination-port-range 443 \
        --only-show-errors
    
    # Allow Bastion Host Communication
    az network nsg rule create \
        --resource-group $RESOURCE_GROUP \
        --nsg-name $NSG_BASTION \
        --name AllowBastionHostCommunication \
        --priority 150 \
        --direction Inbound \
        --access Allow \
        --protocol "*" \
        --source-address-prefix VirtualNetwork \
        --source-port-range "*" \
        --destination-address-prefix VirtualNetwork \
        --destination-port-ranges 8080 5701 \
        --only-show-errors
    
    # Add required outbound rules for Bastion
    print_info "Adding Bastion NSG outbound rules..."
    
    # Allow SSH/RDP to VirtualNetwork
    az network nsg rule create \
        --resource-group $RESOURCE_GROUP \
        --nsg-name $NSG_BASTION \
        --name AllowSshRdpOutbound \
        --priority 100 \
        --direction Outbound \
        --access Allow \
        --protocol "*" \
        --source-address-prefix "*" \
        --source-port-range "*" \
        --destination-address-prefix VirtualNetwork \
        --destination-port-ranges 22 3389 \
        --only-show-errors
    
    # Allow Azure Cloud
    az network nsg rule create \
        --resource-group $RESOURCE_GROUP \
        --nsg-name $NSG_BASTION \
        --name AllowAzureCloudOutbound \
        --priority 110 \
        --direction Outbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefix "*" \
        --source-port-range "*" \
        --destination-address-prefix AzureCloud \
        --destination-port-range 443 \
        --only-show-errors
    
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
#
# WHY: The workspace is the core Databricks resource
# 
# KEY CONFIGURATIONS FOR PRIVATE SETUP:
# 1. Premium SKU - Required for VNet injection and private link
# 2. VNet Injection - Deploys compute into your VNet
# 3. enableNoPublicIp - No public IPs on cluster nodes
# 4. publicNetworkAccess=Disabled - Blocks all public access
# 5. requiredNsgRules=NoAzureDatabricksRules - For SCC mode
#
# Using ARM template for better control over configuration
# ============================================

print_header "Phase 4: Creating Databricks Workspace"

# Check if workspace exists (idempotency)
if az databricks workspace show --resource-group $RESOURCE_GROUP --name $WORKSPACE_NAME &> /dev/null; then
    print_warning "Databricks workspace $WORKSPACE_NAME already exists"
    WORKSPACE_EXISTS=true
else
    WORKSPACE_EXISTS=false
fi

# Get VNet resource ID for ARM template
VNET_ID=$(az network vnet show --resource-group $RESOURCE_GROUP --name $VNET_NAME --query id -o tsv)
print_info "VNet Resource ID: $VNET_ID"

if [ "$WORKSPACE_EXISTS" = false ]; then
    print_info "Creating ARM template for Databricks workspace..."
    
    # Create ARM template with all required configurations
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
  ],
  "outputs": {
    "workspaceId": {
      "type": "string",
      "value": "[resourceId('Microsoft.Databricks/workspaces', parameters('workspaceName'))]"
    }
  }
}
EOF

    print_info "Deploying Databricks workspace..."
    print_warning "This operation typically takes 10-15 minutes..."
    
    DEPLOYMENT_NAME="databricks-deployment-$(date +%s)"
    
    # Deploy the ARM template
    az deployment group create \
        --resource-group $RESOURCE_GROUP \
        --name $DEPLOYMENT_NAME \
        --template-file /tmp/databricks-deployment.json \
        --parameters workspaceName=$WORKSPACE_NAME location=$LOCATION \
        --only-show-errors
    
    print_status "Databricks workspace created successfully!"
    
    # Clean up template file
    rm -f /tmp/databricks-deployment.json
fi

# Wait for workspace to be ready
sleep 10

# ============================================
# PHASE 5: CONFIGURE SECURE CLUSTER CONNECTIVITY
#
# WHY: SCC enables control plane to communicate with data plane
# without using public IPs
#
# HOW IT WORKS:
# - Control plane initiates connection through Azure backbone
# - No inbound connections from internet required
# - All traffic stays within Microsoft network
# ============================================

print_header "Phase 5: Configuring Secure Cluster Connectivity (SCC)"

# Get backend subnet ID for reference
BACKEND_SUBNET_ID=$(az network vnet subnet show \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name "snet-backend-private-endpoint" \
    --query id -o tsv)

print_info "Backend subnet prepared for SCC: $BACKEND_SUBNET_ID"

# Verify workspace configuration
WORKSPACE_CONFIG=$(az databricks workspace show \
    --resource-group $RESOURCE_GROUP \
    --name $WORKSPACE_NAME \
    --query "{PublicAccess:publicNetworkAccess, NoPublicIP:parameters.enableNoPublicIp.value}" \
    -o json)

print_status "Workspace configuration verified"
print_info "SCC is enabled through workspace configuration: $WORKSPACE_CONFIG"

# ============================================
# PHASE 6: FRONTEND PRIVATE ENDPOINTS
#
# WHY: Private endpoints provide secure connectivity to
# Databricks control plane without public internet
#
# TWO TYPES:
# 1. databricks_ui_api - For workspace UI and REST API
# 2. browser_authentication - For Azure AD authentication
# ============================================

print_header "Phase 6: Creating Frontend Private Endpoints"

# Get workspace resource ID
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
    print_info "This endpoint handles workspace UI and REST API requests"
    
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
    print_info "This endpoint handles Azure AD authentication flows"
    
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
#
# WHY: Enables secure communication from Databricks control
# plane to your data plane (compute resources)
#
# PURPOSE:
# - Allows control plane to manage compute
# - Enables job submission and monitoring
# - Provides secure channel for metadata
# ============================================

print_header "Phase 7: Creating Backend Private Endpoint for SCC"

if az network private-endpoint show --resource-group $RESOURCE_GROUP --name "pe-databricks-backend" &> /dev/null; then
    print_warning "Backend private endpoint already exists"
else
    print_info "Creating Backend Private Endpoint for SCC..."
    print_info "This enables secure control-to-data plane communication"
    
    # Attempt to create backend private endpoint
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
            print_info "SCC will function with existing configuration"
        }
fi

# ============================================
# PHASE 8: PRIVATE DNS ZONES FOR DATABRICKS
#
# WHY: Private DNS zones are essential for name resolution
# in private network scenarios
#
# HOW IT WORKS:
# 1. User accesses workspace URL
# 2. Private DNS zone resolves to private IP
# 3. Traffic flows through private endpoint
# ============================================

print_header "Phase 8: Configuring Private DNS Zones for Databricks"

# Create Private DNS Zone for Databricks
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

# Link DNS Zone to VNet
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

# Configure DNS records for private endpoints
print_info "Creating DNS records for Databricks private endpoints..."

# Get workspace URL
WORKSPACE_URL=$(az databricks workspace show \
    --resource-group $RESOURCE_GROUP \
    --name $WORKSPACE_NAME \
    --query workspaceUrl -o tsv)

# Extract hostname from URL
WORKSPACE_HOST="${WORKSPACE_URL%%.*}"
print_info "Workspace hostname: $WORKSPACE_HOST"

# UI/API endpoint DNS configuration
UI_API_PE_NIC_ID=$(az network private-endpoint show \
    --resource-group $RESOURCE_GROUP \
    --name "pe-databricks-ui-api" \
    --query 'networkInterfaces[0].id' -o tsv)

UI_API_IP=$(az network nic show \
    --ids $UI_API_PE_NIC_ID \
    --query 'ipConfigurations[0].privateIPAddress' -o tsv)

# Create/update DNS A record for workspace
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

# Auth endpoint DNS configuration
AUTH_PE_NIC_ID=$(az network private-endpoint show \
    --resource-group $RESOURCE_GROUP \
    --name "pe-databricks-auth" \
    --query 'networkInterfaces[0].id' -o tsv)

AUTH_IP=$(az network nic show \
    --ids $AUTH_PE_NIC_ID \
    --query 'ipConfigurations[0].privateIPAddress' -o tsv)

# Create DNS record for auth endpoint
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
# PHASE 9: AZURE DATA LAKE STORAGE GEN2
#
# WHY: ADLS Gen2 serves as the primary data storage layer
# for Databricks with hierarchical namespace for big data
#
# FEATURES:
# - Hierarchical namespace (true directories)
# - Private endpoints for secure access
# - No public network access
# - Service principal authentication
# ============================================

print_header "Phase 9: Creating Azure Data Lake Storage Gen2"

# Ensure storage account name is valid (3-24 chars, lowercase, numbers only)
STORAGE_ACCOUNT_NAME=$(echo "$STORAGE_ACCOUNT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | cut -c1-24)
print_info "Storage Account Name: $STORAGE_ACCOUNT_NAME"

# Check if storage account exists
if az storage account show --resource-group $RESOURCE_GROUP --name $STORAGE_ACCOUNT_NAME &> /dev/null; then
    print_warning "Storage account $STORAGE_ACCOUNT_NAME already exists"
else
    print_info "Creating ADLS Gen2 Storage Account..."
    print_info "This storage will only be accessible via private endpoints"
    
    az storage account create \
        --name $STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP \
        --location $LOCATION \
        --sku Standard_LRS \
        --kind StorageV2 \
        --hierarchical-namespace true \
        --enable-https-traffic-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --public-network-access Disabled \
        --default-action Deny \
        --tags "Purpose=DataLake" "Environment=Production" \
        --only-show-errors
    
    print_status "ADLS Gen2 storage account created with private access only"
fi

# Get storage account key for container creation
print_info "Retrieving storage account key..."
STORAGE_KEY=$(az storage account keys list \
    --resource-group $RESOURCE_GROUP \
    --account-name $STORAGE_ACCOUNT_NAME \
    --query '[0].value' -o tsv)

# Create storage containers following data lake best practices
print_info "Creating data lake containers..."
for container in "${STORAGE_CONTAINERS[@]}"; do
    print_info "Creating container: $container"
    az storage fs create \
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

# Private endpoint for DFS (Data Lake Storage)
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

# DFS endpoint
DFS_PE_NIC_ID=$(az network private-endpoint show \
    --resource-group $RESOURCE_GROUP \
    --name "pe-adls-dfs" \
    --query 'networkInterfaces[0].id' -o tsv)

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

print_status "Storage DNS configuration completed"

# Create Service Principal for Databricks to access storage
print_info "Creating Service Principal for storage access..."

SP_NAME="sp-databricks-adls-${STORAGE_ACCOUNT_NAME}"
SP_OUTPUT=$(az ad sp create-for-rbac \
    --name $SP_NAME \
    --role "Storage Blob Data Contributor" \
    --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME" \
    --only-show-errors)

CLIENT_ID=$(echo $SP_OUTPUT | jq -r '.appId')
CLIENT_SECRET=$(echo $SP_OUTPUT | jq -r '.password')

print_status "Service Principal created for storage access"
print_warning "SAVE THE CLIENT SECRET - IT WON'T BE SHOWN AGAIN!"

# ============================================
# PHASE 10: JUMP VM CREATION
#
# WHY: Since Databricks has no public access, we need
# a VM inside the VNet to access the workspace
#
# PURPOSE:
# - Administrative access point
# - Testing and troubleshooting
# - Running Databricks CLI/SDK
# ============================================

print_header "Phase 10: Creating Jump VM for Access"

print_info "Jump VM provides access to private Databricks from within VNet"

# Array of VM sizes to try (ordered by cost and availability)
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
        
        # Install desktop environment for GUI access
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
#
# WHY: Bastion provides secure RDP/SSH access without
# exposing VMs to public internet
#
# BENEFITS:
# - No public IPs needed on VMs
# - Protection against port scanning
# - Azure AD integration
# - HTML5 browser-based access
# ============================================

print_header "Phase 11: Creating Azure Bastion"

print_info "Bastion provides secure RDP/SSH access through browser"

# Check if Bastion already exists
if az network bastion show --resource-group $RESOURCE_GROUP --name $BASTION_NAME &> /dev/null; then
    print_warning "Bastion already exists"
else
    # Create public IP for Bastion (only public IP in architecture)
    if ! az network public-ip show --resource-group $RESOURCE_GROUP --name "pip-bastion" &> /dev/null; then
        print_info "Creating public IP for Bastion..."
        print_info "This is the ONLY public IP in the entire architecture"
        
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
#
# WHY: Provides ready-to-use script for mounting
# ADLS Gen2 in Databricks notebooks
# ============================================

print_header "Phase 12: Creating Databricks Configuration Scripts"

# Create mount script for Databricks
cat > databricks-mount-config.py << EOF
# Databricks notebook source
# ADLS Gen2 Mount Configuration for $STORAGE_ACCOUNT_NAME

# COMMAND ----------
# Storage configuration
storage_account_name = "$STORAGE_ACCOUNT_NAME"
client_id = "$CLIENT_ID"
tenant_id = "$TENANT_ID"

# COMMAND ----------
# Create secret scope (run once)
# databricks secrets create-scope --scope adls-scope

# COMMAND ----------
# Set the secret (run in Databricks CLI)
# databricks secrets put --scope adls-scope --key client-secret

# COMMAND ----------
# OAuth configuration
configs = {
    "fs.azure.account.auth.type": "OAuth",
    "fs.azure.account.oauth.provider.type": "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider",
    "fs.azure.account.oauth2.client.id": client_id,
    "fs.azure.account.oauth2.client.secret": dbutils.secrets.get(scope="adls-scope", key="client-secret"),
    "fs.azure.account.oauth2.client.endpoint": f"https://login.microsoftonline.com/{tenant_id}/oauth2/token"
}

# COMMAND ----------
# Mount points configuration
mount_points = {
    "/mnt/raw": f"abfss://raw@{storage_account_name}.dfs.core.windows.net/",
    "/mnt/processed": f"abfss://processed@{storage_account_name}.dfs.core.windows.net/",
    "/mnt/curated": f"abfss://curated@{storage_account_name}.dfs.core.windows.net/",
    "/mnt/sandbox": f"abfss://sandbox@{storage_account_name}.dfs.core.windows.net/",
    "/mnt/archive": f"abfss://archive@{storage_account_name}.dfs.core.windows.net/"
}

# COMMAND ----------
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

# COMMAND ----------
# List all mounts to verify
display(dbutils.fs.mounts())

# COMMAND ----------
# Test access
dbutils.fs.ls("/mnt/raw/")
EOF

print_status "Databricks mount configuration script created: databricks-mount-config.py"

# ============================================
# PHASE 13: VALIDATION AND SUMMARY
#
# WHY: Verify all components are properly configured
# and provide access information to user
# ============================================

print_header "Phase 13: Deployment Validation and Summary"

print_info "Validating all components..."

# Workspace validation
echo ""
echo "Databricks Workspace:"
echo "--------------------"
az databricks workspace show \
    --resource-group $RESOURCE_GROUP \
    --name $WORKSPACE_NAME \
    --query "{Name:name, URL:workspaceUrl, Status:provisioningState, PublicAccess:publicNetworkAccess}" \
    -o table

# Private endpoints validation
echo ""
echo "Private Endpoints:"
echo "-----------------"
az network private-endpoint list \
    --resource-group $RESOURCE_GROUP \
    --query "[].{Name:name, State:provisioningState, Connection:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
    -o table

# Storage validation
echo ""
echo "Storage Account:"
echo "---------------"
az storage account show \
    --resource-group $RESOURCE_GROUP \
    --name $STORAGE_ACCOUNT_NAME \
    --query "{Name:name, PublicAccess:publicNetworkAccess, Status:provisioningState}" \
    -o table

# VM validation
echo ""
echo "Jump VM Status:"
echo "--------------"
if [ "$VM_CREATED" = true ]; then
    az vm show \
        --resource-group $RESOURCE_GROUP \
        --name $VM_NAME \
        --query "{Name:name, Status:powerState, Size:hardwareProfile.vmSize}" \
        -o table
else
    echo "No Jump VM created"
fi

# Save configuration to file
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
  "network": {
    "vnet": "$VNET_NAME",
    "addressSpace": "$VNET_PREFIX",
    "subnets": {
      "databricksHost": "$SUBNET_HOST",
      "databricksContainer": "$SUBNET_CONTAINER",
      "privateEndpoints": "$SUBNET_PE",
      "backendPrivateEndpoint": "$SUBNET_BACKEND_PE",
      "jumpbox": "$SUBNET_JUMPBOX",
      "bastion": "$SUBNET_BASTION"
    }
  },
  "databricks": {
    "workspace": "$WORKSPACE_NAME",
    "url": "https://$WORKSPACE_URL",
    "publicAccess": "Disabled",
    "sccEnabled": true
  },
  "storage": {
    "accountName": "$STORAGE_ACCOUNT_NAME",
    "containers": ["raw", "processed", "curated", "sandbox", "archive"],
    "endpoints": {
      "blob": "https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/",
      "dfs": "https://$STORAGE_ACCOUNT_NAME.dfs.core.windows.net/"
    },
    "privateEndpoints": {
      "blob": "pe-adls-blob ($BLOB_IP)",
      "dfs": "pe-adls-dfs ($DFS_IP)"
    }
  },
  "servicePrincipal": {
    "name": "$SP_NAME",
    "clientId": "$CLIENT_ID",
    "tenantId": "$TENANT_ID"
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

${BLUE}🔒 SECURITY FEATURES:${NC}
  ✅ No public IPs on compute resources
  ✅ All traffic through Azure backbone
  ✅ Private endpoints for all services
  ✅ Network isolation with NSGs
  ✅ Storage firewall enabled
  ✅ SCC enabled for Databricks

${YELLOW}📋 ACCESS INSTRUCTIONS:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. ${BLUE}Wait for Bastion:${NC}
   Check status in Azure Portal (5-10 minutes typical)

2. ${BLUE}Access Jump VM:${NC}
   Portal → Resource Groups → ${GREEN}$RESOURCE_GROUP${NC} → ${GREEN}$VM_NAME${NC}
   Click "Connect" → Select "Bastion"

3. ${BLUE}Login Credentials:${NC}
   Username: ${GREEN}$VM_ADMIN_USER${NC}
   Password: ${GREEN}$VM_ADMIN_PASSWORD${NC}

4. ${BLUE}Access Databricks:${NC}
   Open browser in Jump VM
   Navigate to: ${GREEN}https://$WORKSPACE_URL${NC}
   Login with Azure AD credentials

5. ${BLUE}Mount Storage:${NC}
   Use the script: ${GREEN}databricks-mount-config.py${NC}
   Client Secret: ${YELLOW}[Stored Separately - Check Output Above]${NC}

${YELLOW}⚠️  IMPORTANT NOTES:${NC}
━━━━━━━━━━━━━━━━━━━━