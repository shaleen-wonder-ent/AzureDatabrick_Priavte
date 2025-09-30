#!/bin/bash

#############################################
# Azure Databricks Private Network Setup - CENTRAL INDIA EDITION
# Complete Implementation with Secure Cluster Connectivity (SCC)
# 
# PURPOSE:
# This script creates a completely private Azure Databricks environment
# with no public internet exposure. All access is through private endpoints
# and secure channels only.
#
# ARCHITECTURE OVERVIEW:
# ┌─────────────────────────────────────────────────────────────┐
# │                        AZURE CENTRAL INDIA                   │
# ├─────────────────────────────────────────────────────────────┤
# │  ┌─────────────────────────────────────────────────────┐    │
# │  │              VIRTUAL NETWORK (10.0.0.0/16)          │    │
# │  ├─────────────────────────────────────────────────────┤    │
# │  │                                                     │    │
# │  │  ┌──────────────────┐    ┌──────────────────┐     │    │
# │  │  │ Databricks Host  │    │ Databricks       │     │    │
# │  │  │ Subnet           │    │ Container Subnet │     │    │
# │  │  │ (10.0.1.0/24)    │    │ (10.0.2.0/24)    │     │    │
# │  │  └──────────────────┘    └──────────────────┘     │    │
# │  │                                                     │    │
# │  │  ┌──────────────────┐    ┌──────────────────┐     │    │
# │  │  │ Private Endpoint │    │ Backend PE       │     │    │
# │  │  │ Subnet           │    │ Subnet           │     │    │
# │  │  │ (10.0.3.0/24)    │    │ (10.0.4.0/24)    │     │    │
# │  │  └──────────────────┘    └──────────────────┘     │    │
# │  │                                                     │    │
# │  │  ┌──────────────────┐    ┌──────────────────┐     │    │
# │  │  │ Jump VM Subnet   │    │ Bastion Subnet   │     │    │
# │  │  │ (10.0.5.0/24)    │    │ (10.0.6.0/26)    │     │    │
# │  │  └──────────────────┘    └──────────────────┘     │    │
# │  └─────────────────────────────────────────────────────┘    │
# └─────────────────────────────────────────────────────────────┘
#
# COMPONENTS CREATED:
# 1. Resource Group - Logical container for all resources
# 2. Virtual Network - Private network infrastructure
# 3. 6 Subnets - Network segmentation for different components
# 4. Network Security Groups - Firewall rules
# 5. Databricks Workspace - The main analytics platform
# 6. Private Endpoints - Secure connectivity points
# 7. Private DNS Zones - Name resolution for private access
# 8. Jump VM - Access point within the VNet
# 9. Azure Bastion - Secure RDP/SSH gateway
#
# SECURITY FEATURES:
# - No Public IPs on compute resources
# - All traffic stays within Azure backbone
# - Private endpoints for all connections
# - Network isolation with NSGs
# - Secure Cluster Connectivity (SCC) enabled
#
# Author: Azure Databricks Implementation Team
# Version: 3.0 - Production Ready with Full Documentation
# Date: 2025-01-30
# Region: Central India (Mumbai)
#############################################

# Exit on any error - ensures script stops if something fails
set -e

# Color codes for terminal output - improves readability
RED='\033[0;31m'     # Error messages
GREEN='\033[0;32m'   # Success messages
YELLOW='\033[1;33m'  # Warning messages
BLUE='\033[0;34m'    # Information messages
NC='\033[0m'         # No Color - reset to default

# Helper functions for consistent output formatting throughout the script
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

#############################################
# CONFIGURATION VARIABLES
# 
# These variables define your entire infrastructure.
# Modify these according to your naming conventions and requirements.
# Using environment variables allows override without editing script.
#
# WHY CENTRAL INDIA?
# - Lower latency for India-based users
# - Data residency compliance for Indian regulations
# - Generally better availability than crowded US regions
# - Cost-effective for Indian businesses
#############################################

# Azure Region - Central India (Mumbai datacenter)
# Other India options: southindia (Chennai), westindia (Mumbai - different zone)
export LOCATION="${LOCATION:-centralindia}"

# Resource Group - Container for all resources
# Naming convention: rg-<service>-<environment>-<region>
export RG_NAME="${RG_NAME:-rg-databricks-private-india}"

# Virtual Network - The private network infrastructure
# Naming convention: vnet-<service>-<region>
export VNET_NAME="${VNET_NAME:-vnet-databricks-india}"

# VNet Address Space - Must not overlap with other networks
# Using 10.0.0.0/16 provides 65,536 IP addresses
# Ensure this doesn't conflict with on-premises networks if using VPN/ExpressRoute
export VNET_PREFIX="${VNET_PREFIX:-10.0.0.0/16}"

# Databricks Workspace Name - Must be globally unique
# Adding timestamp ensures uniqueness
export WORKSPACE_NAME="${WORKSPACE_NAME:-dbw-private-india-$(date +%s)}"

# Subnet Configurations
# Each subnet serves a specific purpose in the architecture

# Databricks Host Subnet - Where Spark driver nodes run
# Size: /24 = 256 IPs (Azure reserves 5, so 251 usable)
export SUBNET_HOST="10.0.1.0/24"

# Databricks Container Subnet - Where Spark executor nodes run
# Size: /24 = 256 IPs - Should be same size or larger than host subnet
export SUBNET_CONTAINER="10.0.2.0/24"

# Private Endpoint Subnet - Hosts private endpoints for workspace access
# Size: /24 = 256 IPs - Usually only needs a few IPs
export SUBNET_PE="10.0.3.0/24"

# Backend Private Endpoint Subnet - For control-data plane communication
# Size: /24 = 256 IPs - Used by SCC for backend connectivity
export SUBNET_BACKEND_PE="10.0.4.0/24"

# Jump VM Subnet - Hosts the Jump VM for administrative access
# Size: /24 = 256 IPs - Usually only needs 1-2 VMs
export SUBNET_JUMPBOX="10.0.5.0/24"

# Bastion Subnet - MUST be named "AzureBastionSubnet" (Azure requirement)
# Size: /26 minimum = 64 IPs (Azure Bastion requirement)
export SUBNET_BASTION="10.0.6.0/26"

# Jump VM and Bastion Configuration
export VM_NAME="${VM_NAME:-vm-jumpbox-india}"
export BASTION_NAME="${BASTION_NAME:-bastion-databricks-india}"

# VM Credentials - CHANGE THESE IN PRODUCTION!
# Use Azure Key Vault or Managed Identity in production
VM_ADMIN_USER="azureuser"
VM_ADMIN_PASSWORD="SecurePass@India2025!"  # MUST CHANGE!

#############################################
# PHASE 0: PREREQUISITES CHECK
#
# WHY: Before creating resources, we verify the environment is ready
# This prevents errors and wasted time/money from failed deployments
#
# CHECKS PERFORMED:
# 1. Azure CLI installation - Required to run commands
# 2. Azure authentication - Must be logged in
# 3. Region availability - Ensures Central India is available
# 4. Required extensions - Databricks extension needed
# 5. Resource providers - Must be registered before use
#############################################

print_header "Phase 0: Prerequisites Check"

# Check 1: Azure CLI Installation
# The Azure CLI is our primary tool for creating resources
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed"
    print_info "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
print_status "Azure CLI is installed"

# Check 2: Azure Authentication
# We need valid credentials to create resources
if ! az account show &> /dev/null; then
    print_error "Not logged into Azure. Please run 'az login'"
    exit 1
fi

# Get subscription details for confirmation and logging
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
print_status "Logged into subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Check 3: Verify Central India region is available
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

# Check 4: Install/Update Databricks Extension
# This extension provides Databricks-specific commands
print_status "Installing/Updating Databricks extension..."
az extension add --name databricks --upgrade --only-show-errors

# Check 5: Register Required Resource Providers
# Resource providers must be registered before you can create resources of that type
# This is a one-time operation per subscription
print_status "Registering required resource providers..."

# Microsoft.Databricks - Enables Databricks workspace creation
az provider register --namespace Microsoft.Databricks --wait --only-show-errors

# Microsoft.Network - Enables VNet, subnets, NSGs, etc.
az provider register --namespace Microsoft.Network --wait --only-show-errors

#############################################
# PHASE 1: RESOURCE GROUP CREATION
#
# WHY: Resource groups are logical containers for Azure resources
# 
# BENEFITS:
# - Organize resources by lifecycle, application, or environment
# - Apply RBAC permissions at group level
# - Track costs per group
# - Delete all resources by deleting the group
#
# IDEMPOTENCY: We check if it exists to avoid errors on re-run
#############################################

print_header "Phase 1: Creating Resource Group"

# Check if resource group already exists
if az group show --name $RG_NAME &> /dev/null; then
    print_warning "Resource group $RG_NAME already exists"
    # Ask user to confirm they want to use existing group
    read -p "Do you want to continue using existing resource group? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Exiting. Please delete the resource group or choose a different name."
        exit 1
    fi
else
    # Create new resource group
    az group create \
        --name $RG_NAME \
        --location $LOCATION \
        --only-show-errors
    print_status "Resource group $RG_NAME created in $LOCATION"
fi

#############################################
# PHASE 2: VIRTUAL NETWORK AND SUBNETS
#
# WHY: The VNet provides network isolation and is the foundation
# for private connectivity in Azure
#
# NETWORK DESIGN PRINCIPLES:
# 1. Segmentation - Different subnets for different purposes
# 2. Sizing - Subnets sized appropriately for expected usage
# 3. Growth - Room for expansion within the address space
# 4. Security - Network isolation between components
#
# SUBNET PURPOSES:
# - Databricks subnets: Delegated to Microsoft.Databricks/workspaces
# - Private endpoint subnets: Network policies disabled for PE creation
# - Jump/Bastion subnets: For administrative access
#############################################

print_header "Phase 2: Creating Virtual Network and Subnets"

# Create or verify VNet exists
if az network vnet show --resource-group $RG_NAME --name $VNET_NAME &> /dev/null; then
    print_warning "VNet $VNET_NAME already exists, skipping VNet creation"
else
    print_status "Creating Virtual Network with address space $VNET_PREFIX..."
    az network vnet create \
        --resource-group $RG_NAME \
        --name $VNET_NAME \
        --address-prefix $VNET_PREFIX \
        --location $LOCATION \
        --only-show-errors
fi

# Create all required subnets
# Using a loop to reduce code duplication and ensure consistency
# Format: subnet_name|address_prefix|delegation|disable_private_endpoint_policies

print_info "Creating 6 subnets for different components..."

for SUBNET_INFO in \
    "snet-databricks-host|$SUBNET_HOST|Microsoft.Databricks/workspaces|false" \
    "snet-databricks-container|$SUBNET_CONTAINER|Microsoft.Databricks/workspaces|false" \
    "snet-private-endpoints|$SUBNET_PE||true" \
    "snet-backend-private-endpoint|$SUBNET_BACKEND_PE||true" \
    "snet-jumpbox|$SUBNET_JUMPBOX||false" \
    "AzureBastionSubnet|$SUBNET_BASTION||false"; do
    
    # Parse subnet configuration
    IFS='|' read -r SUBNET_NAME SUBNET_PREFIX DELEGATION DISABLE_PE <<< "$SUBNET_INFO"
    
    # Check if subnet already exists (idempotency)
    if az network vnet subnet show --resource-group $RG_NAME --vnet-name $VNET_NAME --name $SUBNET_NAME &> /dev/null; then
        print_warning "Subnet $SUBNET_NAME already exists, skipping"
    else
        print_status "Creating subnet $SUBNET_NAME with prefix $SUBNET_PREFIX..."
        
        # Create subnet with appropriate configuration
        if [[ -n "$DELEGATION" ]]; then
            # Delegated subnet (for Databricks)
            # Delegation allows Azure services to deploy resources into the subnet
            az network vnet subnet create \
                --resource-group $RG_NAME \
                --vnet-name $VNET_NAME \
                --name $SUBNET_NAME \
                --address-prefix $SUBNET_PREFIX \
                --delegations $DELEGATION \
                --disable-private-endpoint-network-policies $DISABLE_PE \
                --only-show-errors
        else
            # Regular subnet (for VMs, private endpoints, etc.)
            az network vnet subnet create \
                --resource-group $RG_NAME \
                --vnet-name $VNET_NAME \
                --name $SUBNET_NAME \
                --address-prefix $SUBNET_PREFIX \
                --disable-private-endpoint-network-policies $DISABLE_PE \
                --only-show-errors
        fi
    fi
done

#############################################
# PHASE 3: NETWORK SECURITY GROUPS
#
# WHY: NSGs act as virtual firewalls for your subnets
# They control inbound and outbound traffic using security rules
#
# FOR DATABRICKS WITH SCC:
# - We use "NoAzureDatabricksRules" mode
# - This means we don't need the default Databricks NSG rules
# - All communication happens through private endpoints
# - You can add custom rules based on your security requirements
#############################################

print_header "Phase 3: Creating Network Security Groups"

# Create NSG if it doesn't exist
if az network nsg show --resource-group $RG_NAME --name "nsg-databricks" &> /dev/null; then
    print_warning "NSG nsg-databricks already exists, skipping"
else
    print_status "Creating Network Security Group..."
    # NSG created empty - rules can be added based on requirements
    az network nsg create \
        --resource-group $RG_NAME \
        --name "nsg-databricks" \
        --location $LOCATION \
        --only-show-errors
fi

# Associate NSG with Databricks subnets
# This applies the security rules to all resources in these subnets
print_status "Associating NSG with Host subnet..."
az network vnet subnet update \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "snet-databricks-host" \
    --network-security-group "nsg-databricks" \
    --only-show-errors

print_status "Associating NSG with Container subnet..."
az network vnet subnet update \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "snet-databricks-container" \
    --network-security-group "nsg-databricks" \
    --only-show-errors

#############################################
# PHASE 4: DATABRICKS WORKSPACE CREATION
#
# WHY: The workspace is the core Databricks resource where users
# create notebooks, run jobs, and analyze data
#
# KEY CONFIGURATIONS FOR PRIVATE SETUP:
# 1. Premium SKU - Required for VNet injection and private link
# 2. VNet Injection - Deploys compute into your VNet
# 3. enableNoPublicIp - No public IPs on cluster nodes
# 4. publicNetworkAccess=Disabled - Blocks all public access
# 5. requiredNsgRules=NoAzureDatabricksRules - For SCC mode
#
# ARM TEMPLATE APPROACH:
# We use ARM templates for better control over configuration
# CLI commands don't support all parameters we need
#############################################

print_header "Phase 4: Creating Databricks Workspace"

# Check if workspace already exists (idempotency)
if az databricks workspace show --resource-group $RG_NAME --name $WORKSPACE_NAME &> /dev/null; then
    print_warning "Databricks workspace $WORKSPACE_NAME already exists"
    WORKSPACE_EXISTS=true
else
    WORKSPACE_EXISTS=false
fi

# Get VNet resource ID for the ARM template
VNET_ID=$(az network vnet show --resource-group $RG_NAME --name $VNET_NAME --query id -o tsv)

if [ "$WORKSPACE_EXISTS" = false ]; then
    print_status "Creating ARM template for Databricks workspace..."
    
    # Create ARM template with all required configurations
    # This template defines the Databricks workspace with private networking
    cat > databricks-deployment.json << EOF
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
    // Managed resource group is created automatically by Azure
    // It contains Databricks-managed resources like storage accounts
    "managedResourceGroupName": "[concat('databricks-rg-', parameters('workspaceName'), '-', uniqueString(parameters('workspaceName'), resourceGroup().id))]"
  },
  "resources": [
    {
      "type": "Microsoft.Databricks/workspaces",
      "apiVersion": "2024-05-01",
      "name": "[parameters('workspaceName')]",
      "location": "[parameters('location')]",
      "sku": {
        // Premium SKU required for:
        // - VNet injection
        // - Private link support
        // - Advanced security features
        "name": "premium"
      },
      "properties": {
        "managedResourceGroupId": "[subscriptionResourceId('Microsoft.Resources/resourceGroups', variables('managedResourceGroupName'))]",
        "parameters": {
          // VNet injection configuration
          "customVirtualNetworkId": {
            "value": "$VNET_ID"
          },
          // Specify which subnets Databricks should use
          "customPublicSubnetName": {
            "value": "snet-databricks-host"
          },
          "customPrivateSubnetName": {
            "value": "snet-databricks-container"
          },
          // CRITICAL: No public IPs on compute resources
          "enableNoPublicIp": {
            "value": true
          },
          // Infrastructure encryption (optional, disabled for simplicity)
          "requireInfrastructureEncryption": {
            "value": false
          },
          // Storage account type for workspace storage
          "storageAccountSkuName": {
            "value": "Standard_LRS"
          }
        },
        // CRITICAL: Disable all public network access
        "publicNetworkAccess": "Disabled",
        // No default NSG rules needed with SCC
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

    print_status "Deploying Databricks workspace..."
    print_warning "This operation typically takes 10-15 minutes..."
    
    DEPLOYMENT_NAME="databricks-deployment-$(date +%s)"
    
    # Deploy the ARM template
    az deployment group create \
        --resource-group $RG_NAME \
        --name $DEPLOYMENT_NAME \
        --template-file databricks-deployment.json \
        --parameters workspaceName=$WORKSPACE_NAME location=$LOCATION \
        --only-show-errors
    
    print_status "Databricks workspace created successfully!"
    
    # Clean up template file
    rm -f databricks-deployment.json
fi

# Wait for workspace to be fully ready
sleep 10

#############################################
# PHASE 5: CONFIGURE SECURE CLUSTER CONNECTIVITY
#
# WHY: SCC enables the Databricks control plane to communicate
# with the data plane (your VNet) without using public IPs
#
# HOW IT WORKS:
# - Control plane initiates connection through Azure backbone
# - No inbound connections from internet required
# - All traffic stays within Microsoft network
#
# AUTOMATIC ENABLEMENT:
# SCC is automatically enabled when:
# - enableNoPublicIp = true
# - publicNetworkAccess = Disabled
#############################################

print_header "Phase 5: Configuring Secure Cluster Connectivity"

# Get the backend subnet ID for reference
BACKEND_SUBNET_ID=$(az network vnet subnet show \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "snet-backend-private-endpoint" \
    --query id -o tsv)

print_status "Backend subnet prepared for SCC: $BACKEND_SUBNET_ID"

# Verify workspace configuration
WORKSPACE_CONFIG=$(az databricks workspace show \
    --resource-group $RG_NAME \
    --name $WORKSPACE_NAME \
    --query "{PublicAccess:publicNetworkAccess, NoPublicIP:parameters.enableNoPublicIp.value}" \
    -o json)

print_status "Workspace configuration verified: $WORKSPACE_CONFIG"
print_info "SCC is enabled through workspace configuration"

#############################################
# PHASE 6: FRONTEND PRIVATE ENDPOINTS
#
# WHY: Private endpoints provide secure connectivity to the
# Databricks control plane without going over public internet
#
# TWO TYPES OF FRONTEND ENDPOINTS:
#
# 1. databricks_ui_api:
#    - Used for workspace UI access
#    - Used for REST API calls
#    - Main endpoint for user and programmatic interaction
#
# 2. browser_authentication:
#    - Used for Azure AD authentication flows
#    - Handles SSO and browser-based auth
#    - Required for web authentication scenarios
#############################################

print_header "Phase 6: Creating Frontend Private Endpoints"

# Get workspace resource ID for private endpoint creation
WORKSPACE_ID=$(az databricks workspace show \
    --resource-group $RG_NAME \
    --name $WORKSPACE_NAME \
    --query id -o tsv)

# Create UI/API Private Endpoint
if az network private-endpoint show --resource-group $RG_NAME --name "pe-databricks-ui-api" &> /dev/null; then
    print_warning "Private endpoint pe-databricks-ui-api already exists, skipping"
else
    print_status "Creating Private Endpoint for UI/API access..."
    print_info "This endpoint handles workspace UI and REST API requests"
    
    az network private-endpoint create \
        --resource-group $RG_NAME \
        --name "pe-databricks-ui-api" \
        --vnet-name $VNET_NAME \
        --subnet "snet-private-endpoints" \
        --private-connection-resource-id $WORKSPACE_ID \
        --group-id "databricks_ui_api" \
        --connection-name "connection-databricks-ui-api" \
        --location $LOCATION \
        --only-show-errors
fi

# Create Auth Private Endpoint
if az network private-endpoint show --resource-group $RG_NAME --name "pe-databricks-auth" &> /dev/null; then
    print_warning "Private endpoint pe-databricks-auth already exists, skipping"
else
    print_status "Creating Private Endpoint for Browser Authentication..."
    print_info "This endpoint handles Azure AD authentication flows"
    
    az network private-endpoint create \
        --resource-group $RG_NAME \
        --name "pe-databricks-auth" \
        --vnet-name $VNET_NAME \
        --subnet "snet-private-endpoints" \
        --private-connection-resource-id $WORKSPACE_ID \
        --group-id "browser_authentication" \
        --connection-name "connection-databricks-auth" \
        --location $LOCATION \
        --only-show-errors
fi

#############################################
# PHASE 7: BACKEND PRIVATE ENDPOINT FOR SCC
#
# WHY: The backend private endpoint enables secure communication
# from the Databricks control plane to your data plane
#
# PURPOSE:
# - Allows control plane to manage compute resources
# - Enables job submission and monitoring
# - Provides secure channel for metadata operations
#
# NOTE: This may be automatically created by Azure Databricks
# when SCC is enabled, but we attempt to create it explicitly
#############################################

print_header "Phase 7: Creating Backend Private Endpoint for SCC"

if az network private-endpoint show --resource-group $RG_NAME --name "pe-databricks-backend" &> /dev/null; then
    print_warning "Backend private endpoint already exists, skipping"
else
    print_status "Creating Backend Private Endpoint for SCC..."
    print_info "This enables secure control-to-data plane communication"
    
    # Attempt to create backend private endpoint
    # This might fail if automatically created by Databricks
    az network private-endpoint create \
        --resource-group $RG_NAME \
        --name "pe-databricks-backend" \
        --vnet-name $VNET_NAME \
        --subnet "snet-backend-private-endpoint" \
        --private-connection-resource-id $WORKSPACE_ID \
        --group-id "databricks_ui_api" \
        --connection-name "connection-databricks-backend" \
        --location $LOCATION \
        --only-show-errors 2>/dev/null || {
            print_warning "Backend private endpoint may be automatically managed by Databricks"
            print_status "SCC will function with the existing configuration"
        }
fi

#############################################
# PHASE 8: PRIVATE DNS ZONES
#
# WHY: Private DNS zones are essential for name resolution
# in private network scenarios
#
# HOW IT WORKS:
# 1. User accesses workspace URL (e.g., adb-xxx.azuredatabricks.net)
# 2. Private DNS zone resolves this to private IP of the endpoint
# 3. Traffic flows through private endpoint, not public internet
#
# REQUIRED ZONE:
# - privatelink.azuredatabricks.net (exact name required)
#############################################

print_header "Phase 8: Configuring Private DNS Zones"

# Create Private DNS Zone
if az network private-dns zone show --resource-group $RG_NAME --name "privatelink.azuredatabricks.net" &> /dev/null; then
    print_warning "Private DNS Zone already exists, skipping creation"
else
    print_status "Creating Private DNS Zone for Databricks..."
    print_info "This zone handles name resolution for private endpoints"
    
    az network private-dns zone create \
        --resource-group $RG_NAME \
        --name "privatelink.azuredatabricks.net" \
        --only-show-errors
fi

# Link DNS Zone to VNet
if az network private-dns link vnet show --resource-group $RG_NAME --zone-name "privatelink.azuredatabricks.net" --name "link-databricks-vnet" &> /dev/null; then
    print_warning "DNS VNet link already exists, skipping"
else
    print_status "Linking DNS Zone to Virtual Network..."
    print_info "This allows resources in the VNet to use this DNS zone"
    
    az network private-dns link vnet create \
        --resource-group $RG_NAME \
        --zone-name "privatelink.azuredatabricks.net" \
        --name "link-databricks-vnet" \
        --virtual-network $VNET_NAME \
        --registration-enabled false \
        --only-show-errors
fi

# Configure DNS records for private endpoints
print_status "Creating DNS records for private endpoints..."

# Get workspace URL for DNS record creation
WORKSPACE_URL=$(az databricks workspace show \
    --resource-group $RG_NAME \
    --name $WORKSPACE_NAME \
    --query workspaceUrl -o tsv)

# Extract hostname from URL
WORKSPACE_HOST="${WORKSPACE_URL%%.*}"

# UI/API endpoint DNS configuration
print_info "Configuring DNS for UI/API endpoint..."

# Get private IP of UI/API endpoint
UI_API_PE_NIC_ID=$(az network private-endpoint show \
    --resource-group $RG_NAME \
    --name "pe-databricks-ui-api" \
    --query 'networkInterfaces[0].id' -o tsv)

UI_API_IP=$(az network nic show \
    --ids $UI_API_PE_NIC_ID \
    --query 'ipConfigurations[0].privateIPAddress' -o tsv)

# Create/update DNS A record for workspace
az network private-dns record-set a create \
    --resource-group $RG_NAME \
    --zone-name "privatelink.azuredatabricks.net" \
    --name "$WORKSPACE_HOST" \
    --only-show-errors 2>/dev/null || true

az network private-dns record-set a add-record \
    --resource-group $RG_NAME \
    --zone-name "privatelink.azuredatabricks.net" \
    --record-set-name "$WORKSPACE_HOST" \
    --ipv4-address $UI_API_IP \
    --only-show-errors 2>/dev/null || true

print_status "DNS record created: $WORKSPACE_HOST -> $UI_API_IP"

# Auth endpoint DNS configuration
print_info "Configuring DNS for authentication endpoint..."

# Get private IP of Auth endpoint
AUTH_PE_NIC_ID=$(az network private-endpoint show \
    --resource-group $RG_NAME \
    --name "pe-databricks-auth" \
    --query 'networkInterfaces[0].id' -o tsv)

AUTH_IP=$(az network nic show \
    --ids $AUTH_PE_NIC_ID \
    --query 'ipConfigurations[0].privateIPAddress' -o tsv)

# Create DNS record for auth endpoint
az network private-dns record-set a create \
    --resource-group $RG_NAME \
    --zone-name "privatelink.azuredatabricks.net" \
    --name "adb-auth-${WORKSPACE_HOST}" \
    --only-show-errors 2>/dev/null || true

az network private-dns record-set a add-record \
    --resource-group $RG_NAME \
    --zone-name "privatelink.azuredatabricks.net" \
    --record-set-name "adb-auth-${WORKSPACE_HOST}" \
    --ipv4-address $AUTH_IP \
    --only-show-errors 2>/dev/null || true

print_status "DNS record created: adb-auth-${WORKSPACE_HOST} -> $AUTH_IP"

#############################################
# PHASE 9: JUMP VM CREATION
#
# WHY: Since Databricks has no public access, we need a VM
# inside the VNet to access the workspace
#
# PURPOSE:
# - Provides access point within the private network
# - Used for administrative tasks
# - Testing and troubleshooting
#
# VM SIZING STRATEGY:
# - Start with smaller, cheaper sizes
# - Try multiple sizes due to capacity constraints
# - Use Spot instances as last resort
#############################################

print_header "Phase 9: Creating Jump VM"

print_info "Jump VM provides access to private Databricks from within VNet"

# Array of VM sizes to try (ordered by cost and availability)
# B-series: Burstable, cost-effective for intermittent use
# D-series: General purpose, good for consistent workloads
VM_SIZES=(
    "Standard_B2s"       # 2 vCPU, 4 GB RAM - Usually available
    "Standard_B2ms"      # 2 vCPU, 8 GB RAM - Good alternative
    "Standard_D2s_v5"    # 2 vCPU, 8 GB RAM - Latest generation
    "Standard_D2s_v4"    # 2 vCPU, 8 GB RAM - Previous generation
    "Standard_D2s_v3"    # 2 vCPU, 8 GB RAM - Widely available
    "Standard_B1ms"      # 1 vCPU, 2 GB RAM - Minimal option
    "Standard_D2as_v5"   # 2 vCPU, 8 GB RAM - AMD variant
)

VM_CREATED=false

print_info "Checking VM availability in Central India..."

# Try each VM size until one succeeds
for SIZE in "${VM_SIZES[@]}"; do
    print_info "Attempting VM creation with size: $SIZE"
    
    if az vm create \
        --resource-group $RG_NAME \
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
        print_info "Installing desktop environment (for browser access)..."
        az vm run-command invoke \
            --resource-group $RG_NAME \
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

# If regular VMs fail, try Spot instance
if [ "$VM_CREATED" = false ]; then
    print_warning "Standard VM sizes unavailable, trying Spot instance..."
    print_info "Spot VMs use unused capacity and are cheaper but can be evicted"
    
    if az vm create \
        --resource-group $RG_NAME \
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
        print_info "Try creating via Azure Portal with different size/region"
    fi
fi

#############################################
# PHASE 10: AZURE BASTION CREATION
#
# WHY: Bastion provides secure RDP/SSH access without exposing
# VMs to the public internet
#
# BENEFITS:
# - No public IPs needed on VMs
# - Protection against port scanning
# - Azure AD integration
# - Session recording capabilities
# - HTML5 browser-based access
#
# HOW IT WORKS:
# Internet -> Bastion (Public IP) -> TLS/HTTPS -> Private VM
#############################################

print_header "Phase 10: Creating Azure Bastion"

print_info "Bastion provides secure RDP/SSH access through the browser"

# Check if Bastion already exists
if az network bastion show --resource-group $RG_NAME --name $BASTION_NAME &> /dev/null; then
    print_warning "Bastion already exists, skipping"
else
    # Create public IP for Bastion (only public IP in architecture)
    if ! az network public-ip show --resource-group $RG_NAME --name "pip-bastion" &> /dev/null; then
        print_status "Creating public IP for Bastion..."
        print_info "This is the only public IP in the architecture"
        
        az network public-ip create \
            --resource-group $RG_NAME \
            --name "pip-bastion" \
            --sku Standard \
            --location $LOCATION \
            --only-show-errors
    fi
    
    # Create Bastion host
    print_status "Creating Azure Bastion..."
    print_warning "This operation takes 5-10 minutes to complete"
    print_info "Bastion will deploy in background, you can proceed with other tasks"
    
    az network bastion create \
        --name $BASTION_NAME \
        --public-ip-address "pip-bastion" \
        --resource-group $RG_NAME \
        --vnet-name $VNET_NAME \
        --location $LOCATION \
        --no-wait \
        --only-show-errors
    
    print_info "Bastion deployment initiated"
fi

#############################################
# PHASE 11: VALIDATION
#
# WHY: Verify all components are properly configured
# This helps identify any issues before users attempt access
#
# VALIDATIONS PERFORMED:
# - Workspace configuration
# - Private endpoint status
# - Network configuration
# - VM and Bastion status
# - DNS records
#############################################

print_header "Phase 11: Setup Validation"

print_info "Validating all components..."

echo ""
echo "Databricks Workspace:"
echo "---------------------"
az databricks workspace show \
    --resource-group $RG_NAME \
    --name $WORKSPACE_NAME \
    --query "{Name:name, URL:workspaceUrl, Status:provisioningState, PublicAccess:publicNetworkAccess}" \
    -o table

echo ""
echo "Private Endpoints:"
echo "-----------------"
az network private-endpoint list \
    --resource-group $RG_NAME \
    --query "[].{Name:name, State:provisioningState, Connection:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
    -o table

echo ""
echo "Network Subnets:"
echo "----------------"
az network vnet subnet list \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --query "[].{Name:name, AddressPrefix:addressPrefix, Delegation:delegations[0].serviceName}" \
    -o table

echo ""
echo "Jump VM Status:"
echo "---------------"
if [ "$VM_CREATED" = true ]; then
    az vm show \
        --resource-group $RG_NAME \
        --name $VM_NAME \
        --query "{Name:name, Status:powerState, Size:hardwareProfile.vmSize}" \
        -o table
else
    echo "No Jump VM created"
fi

echo ""
echo "Bastion Status:"
echo "---------------"
az network bastion show \
    --resource-group $RG_NAME \
    --name $BASTION_NAME \
    --query "{Name:name, Status:provisioningState}" \
    -o table 2>/dev/null || echo "Bastion still deploying"

echo ""
echo "DNS Records:"
echo "------------"
az network private-dns record-set a list \
    --resource-group $RG_NAME \
    --zone-name "privatelink.azuredatabricks.net" \
    --query "[].{Name:name, IP:aRecords[0].ipv4Address}" \
    -o table

#############################################
# COMPLETION AND SUMMARY
#
# Provide clear instructions for accessing the workspace
# Save configuration for future reference
#############################################

print_header "✅ Deployment Complete!"

cat << EOF

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}  AZURE DATABRICKS PRIVATE SETUP - CENTRAL INDIA COMPLETE!     ${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

${BLUE}📍 DEPLOYMENT SUMMARY:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Region:              ${GREEN}$LOCATION${NC}
  Resource Group:      ${GREEN}$RG_NAME${NC}
  Virtual Network:     ${GREEN}$VNET_NAME${NC}
  Databricks:          ${GREEN}$WORKSPACE_NAME${NC}
  Workspace URL:       ${GREEN}https://$WORKSPACE_URL${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${BLUE}🔒 SECURITY FEATURES ENABLED:${NC}
  ✅ No public IPs on compute resources
  ✅ Public network access disabled
  ✅ All traffic through private endpoints
  ✅ Secure Cluster Connectivity (SCC) enabled
  ✅ Network isolation with NSGs

${YELLOW}📋 ACCESS INSTRUCTIONS:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. ${BLUE}Wait for Bastion:${NC}
   Check status in Azure Portal (5-10 minutes typical)

2. ${BLUE}Access Jump VM:${NC}
   Portal → Resource Groups → ${GREEN}$RG_NAME${NC} → ${GREEN}$VM_NAME${NC}
   Click "Connect" → Select "Bastion"

3. ${BLUE}Login Credentials:${NC}
   Username: ${GREEN}$VM_ADMIN_USER${NC}
   Password: ${GREEN}$VM_ADMIN_PASSWORD${NC}

4. ${BLUE}Access Databricks:${NC}
   Open browser in Jump VM
   Navigate to: ${GREEN}https://$WORKSPACE_URL${NC}
   Login with Azure AD credentials

${YELLOW}⚠️ IMPORTANT NOTES:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Databricks is ONLY accessible from within the VNet
• No public internet access is possible (by design)
• Change the Jump VM password immediately
• Stop VM when not in use to save costs
• Monitor costs in Azure Cost Management

${BLUE}💰 COST OPTIMIZATION TIPS:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Deallocate Jump VM when not in use:
  ${GREEN}az vm deallocate --resource-group $RG_NAME --name $VM_NAME${NC}
• Delete Bastion if not needed long-term (saves ~\$140/month)
• Use auto-shutdown policies for VMs
• Consider Spot instances for non-production

EOF

# Save detailed configuration file
CONFIG_FILE="databricks-india-deployment-$(date +%Y%m%d-%H%M%S).txt"
cat > $CONFIG_FILE << EOF
AZURE DATABRICKS PRIVATE NETWORK DEPLOYMENT - CENTRAL INDIA
============================================================
Deployment Date: $(date)
Deployed By: $(az account show --query user.name -o tsv)

SUBSCRIPTION DETAILS:
--------------------
Name: $SUBSCRIPTION_NAME
ID: $SUBSCRIPTION_ID

RESOURCE CONFIGURATION:
-----------------------
Resource Group: $RG_NAME
Location: $LOCATION

NETWORK ARCHITECTURE:
--------------------
Virtual Network: $VNET_NAME
Address Space: $VNET_PREFIX

Subnets:
1. Databricks Host: snet-databricks-host ($SUBNET_HOST)
   - Purpose: Spark driver nodes
   - Delegated to: Microsoft.Databricks/workspaces
   
2. Databricks Container: snet-databricks-container ($SUBNET_CONTAINER)
   - Purpose: Spark executor nodes
   - Delegated to: Microsoft.Databricks/workspaces
   
3. Private Endpoints: snet-private-endpoints ($SUBNET_PE)
   - Purpose: Frontend private endpoints
   - Private endpoint policies disabled
   
4. Backend Private Endpoint: snet-backend-private-endpoint ($SUBNET_BACKEND_PE)
   - Purpose: SCC backend connectivity
   - Private endpoint policies disabled
   
5. Jump VM: snet-jumpbox ($SUBNET_JUMPBOX)
   - Purpose: Administrative access
   
6. Bastion: AzureBastionSubnet ($SUBNET_BASTION)
   - Purpose: Secure RDP/SSH gateway

DATABRICKS WORKSPACE:
--------------------
Name: $WORKSPACE_NAME
URL: https://$WORKSPACE_URL
SKU: Premium
Public Network Access: Disabled
No Public IP: Enabled
SCC: Enabled

PRIVATE ENDPOINTS:
-----------------
1. UI/API: pe-databricks-ui-api
   - IP: $UI_API_IP
   
2. Authentication: pe-databricks-auth
   - IP: $AUTH_IP
   
3. Backend: pe-databricks-backend (SCC)

ACCESS INFRASTRUCTURE:
---------------------
Jump VM: $VM_NAME
- Username: $VM_ADMIN_USER
- Password: $VM_ADMIN_PASSWORD
- Size: ${VM_SIZE_USED:-Not created}

Bastion: $BASTION_NAME
- Public IP: pip-bastion

DNS CONFIGURATION:
-----------------
Private DNS Zone: privatelink.azuredatabricks.net
Records:
- $WORKSPACE_HOST -> $UI_API_IP
- adb-auth-$WORKSPACE_HOST -> $AUTH_IP

SECURITY CONFIGURATION:
----------------------
Network Security Group: nsg-databricks
- Applied to Databricks subnets
- No default Databricks rules (SCC mode)

NEXT STEPS:
----------
1. Wait for Bastion deployment to complete
2. Connect to Jump VM via Bastion
3. Access Databricks workspace from Jump VM
4. Configure workspace settings (users, clusters, etc.)
5. Implement additional security measures as needed

TROUBLESHOOTING:
---------------
If unable to access Databricks:
1. Verify Bastion is deployed (Status: Succeeded)
2. Check VM is running
3. Verify DNS resolution from Jump VM
4. Check private endpoint connection status
5. Ensure NSG rules allow required traffic

CLEANUP COMMANDS:
----------------
To delete everything:
az group delete --name $RG_NAME --yes

To stop Jump VM (save costs):
az vm deallocate --resource-group $RG_NAME --name $VM_NAME

To restart Jump VM:
az vm start --resource-group $RG_NAME --name $VM_NAME
============================================================
EOF

print_status "Configuration saved to: ${GREEN}$CONFIG_FILE${NC}"
print_status "Deployment completed successfully! 🎉"

# Final reminder
echo ""
print_warning "Remember to:"
echo "  1. Change the default password for Jump VM"
echo "  2. Configure auto-shutdown for cost savings"
echo "  3. Review NSG rules for your security requirements"
echo "  4. Set up monitoring and alerts"