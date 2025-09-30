# Azure Databricks Private Network Deployment Guide

## Complete Implementation with Secure Cluster Connectivity (SCC) - Central India Edition

### Table of Contents
1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Phase 1: Resource Group](#phase-1-resource-group)
4. [Phase 2: Virtual Network and Subnets](#phase-2-virtual-network-and-subnets)
5. [Phase 3: Network Security Groups](#phase-3-network-security-groups)
6. [Phase 4: Databricks Workspace](#phase-4-databricks-workspace)
7. [Phase 5: Secure Cluster Connectivity](#phase-5-secure-cluster-connectivity)
8. [Phase 6: Frontend Private Endpoints](#phase-6-frontend-private-endpoints)
9. [Phase 7: Backend Private Endpoint](#phase-7-backend-private-endpoint)
10. [Phase 8: Private DNS Configuration](#phase-8-private-dns-configuration)
11. [Phase 9: Jump VM Creation](#phase-9-jump-vm-creation)
12. [Phase 10: Azure Bastion](#phase-10-azure-bastion)
13. [Phase 11: Validation](#phase-11-validation)
14. [Access Instructions](#access-instructions)
15. [Cost Optimization](#cost-optimization)
16. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools
- **Azure CLI** (version 2.0 or later)
- **Azure subscription** with sufficient quota in Central India region
- **Contributor or Owner** role on the subscription
- **Databricks extension** for Azure CLI

### Initial Setup Commands

```bash
# 1. Login to Azure
az login

# 2. Set subscription (if you have multiple)
az account set --subscription "YOUR_SUBSCRIPTION_NAME"

# 3. Install Databricks extension
az extension add --name databricks --upgrade

# 4. Register resource providers
az provider register --namespace Microsoft.Databricks --wait
az provider register --namespace Microsoft.Network --wait
```

### Environment Variables (Modify as needed)

```bash
# Azure Region - Central India (Mumbai datacenter)
export LOCATION="centralindia"

# Resource Group - Container for all resources
export RG_NAME="rg-databricks-private-india"

# Virtual Network - The private network infrastructure
export VNET_NAME="vnet-databricks-india"

# VNet Address Space - Must not overlap with other networks
export VNET_PREFIX="10.0.0.0/16"

# Databricks Workspace Name - Must be globally unique
export WORKSPACE_NAME="dbw-private-india-$(date +%s)"

# Subnet Configurations
export SUBNET_HOST="10.0.1.0/24"
export SUBNET_CONTAINER="10.0.2.0/24"
export SUBNET_PE="10.0.3.0/24"
export SUBNET_BACKEND_PE="10.0.4.0/24"
export SUBNET_JUMPBOX="10.0.5.0/24"
export SUBNET_BASTION="10.0.6.0/26"

# Jump VM Configuration
export VM_NAME="vm-jumpbox-india"
export BASTION_NAME="bastion-databricks-india"
export VM_ADMIN_USER="azureuser"
export VM_ADMIN_PASSWORD="SecurePass@India2025!"  # CHANGE THIS!
```

---

## Architecture Overview

This script creates a completely private Azure Databricks environment with no public internet exposure. All access is through private endpoints and secure channels only.

```
┌─────────────────────────────────────────────────────────────┐
│                        AZURE CENTRAL INDIA                   │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │              VIRTUAL NETWORK (10.0.0.0/16)          │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │                                                     │    │
│  │  ┌──────────────────┐    ┌──────────────────┐     │    │
│  │  │ Databricks Host  │    │ Databricks       │     │    │
│  │  │ Subnet           │    │ Container Subnet │     │    │
│  │  │ (10.0.1.0/24)    │    │ (10.0.2.0/24)    │     │    │
│  │  └──────────────────┘    └──────────────────┘     │    │
│  │                                                     │    │
│  │  ┌──────────────────┐    ┌──────────────────┐     │    │
│  │  │ Private Endpoint │    │ Backend PE       │     │    │
│  │  │ Subnet           │    │ Subnet           │     │    │
│  │  │ (10.0.3.0/24)    │    │ (10.0.4.0/24)    │     │    │
│  │  └──────────────────┘    └──────────────────┘     │    │
│  │                                                     │    │
│  │  ┌──────────────────┐    ┌──────────────────┐     │    │
│  │  │ Jump VM Subnet   │    │ Bastion Subnet   │     │    │
│  │  │ (10.0.5.0/24)    │    │ (10.0.6.0/26)    │     │    │
│  │  └──────────────────┘    └──────────────────┘     │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Components Created:
1. **Resource Group** - Logical container for all resources
2. **Virtual Network** - Private network infrastructure
3. **6 Subnets** - Network segmentation for different components
4. **Network Security Groups** - Firewall rules
5. **Databricks Workspace** - The main analytics platform
6. **Private Endpoints** - Secure connectivity points
7. **Private DNS Zones** - Name resolution for private access
8. **Jump VM** - Access point within the VNet
9. **Azure Bastion** - Secure RDP/SSH gateway

### Security Features:
- ✅ No Public IPs on compute resources
- ✅ All traffic stays within Azure backbone
- ✅ Private endpoints for all connections
- ✅ Network isolation with NSGs
- ✅ Secure Cluster Connectivity (SCC) enabled

---

## Phase 1: Resource Group

Create a logical container for all Azure resources.

```bash
# Check if resource group exists
if az group show --name $RG_NAME &> /dev/null; then
    echo "Resource group $RG_NAME already exists"
else
    # Create new resource group
    az group create \
        --name $RG_NAME \
        --location $LOCATION
    echo "Resource group $RG_NAME created in $LOCATION"
fi
```

**Benefits:**
- Organize resources by lifecycle, application, or environment
- Apply RBAC permissions at group level
- Track costs per group
- Delete all resources by deleting the group

---

## Phase 2: Virtual Network and Subnets

Create the foundational network infrastructure with proper segmentation.

### Create Virtual Network

```bash
# Create VNet with address space
az network vnet create \
    --resource-group $RG_NAME \
    --name $VNET_NAME \
    --address-prefix $VNET_PREFIX \
    --location $LOCATION
```

### Create Subnets

```bash
# 1. Databricks Host Subnet (Spark driver nodes)
az network vnet subnet create \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "snet-databricks-host" \
    --address-prefix $SUBNET_HOST \
    --delegations "Microsoft.Databricks/workspaces"

# 2. Databricks Container Subnet (Spark executor nodes)
az network vnet subnet create \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "snet-databricks-container" \
    --address-prefix $SUBNET_CONTAINER \
    --delegations "Microsoft.Databricks/workspaces"

# 3. Private Endpoint Subnet
az network vnet subnet create \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "snet-private-endpoints" \
    --address-prefix $SUBNET_PE \
    --disable-private-endpoint-network-policies true

# 4. Backend Private Endpoint Subnet
az network vnet subnet create \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "snet-backend-private-endpoint" \
    --address-prefix $SUBNET_BACKEND_PE \
    --disable-private-endpoint-network-policies true

# 5. Jump VM Subnet
az network vnet subnet create \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "snet-jumpbox" \
    --address-prefix $SUBNET_JUMPBOX

# 6. Bastion Subnet (MUST be named "AzureBastionSubnet")
az network vnet subnet create \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "AzureBastionSubnet" \
    --address-prefix $SUBNET_BASTION
```

**Subnet Purposes:**
- **Databricks subnets**: Delegated to Microsoft.Databricks/workspaces
- **Private endpoint subnets**: Network policies disabled for PE creation
- **Jump/Bastion subnets**: For administrative access

---

## Phase 3: Network Security Groups

Create virtual firewalls to control traffic to your subnets.

```bash
# Create NSG
az network nsg create \
    --resource-group $RG_NAME \
    --name "nsg-databricks" \
    --location $LOCATION

# Associate NSG with Databricks subnets
az network vnet subnet update \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "snet-databricks-host" \
    --network-security-group "nsg-databricks"

az network vnet subnet update \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "snet-databricks-container" \
    --network-security-group "nsg-databricks"
```

**For Databricks with SCC:**
- We use "NoAzureDatabricksRules" mode
- All communication happens through private endpoints
- Custom rules can be added based on security requirements

---

## Phase 4: Databricks Workspace

Create the Databricks workspace with private networking configuration.

### Create ARM Template

```bash
# Get VNet resource ID
VNET_ID=$(az network vnet show --resource-group $RG_NAME --name $VNET_NAME --query id -o tsv)

# Create ARM template
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
```

### Deploy Workspace

```bash
# Deploy the ARM template
DEPLOYMENT_NAME="databricks-deployment-$(date +%s)"

az deployment group create \
    --resource-group $RG_NAME \
    --name $DEPLOYMENT_NAME \
    --template-file databricks-deployment.json \
    --parameters workspaceName=$WORKSPACE_NAME location=$LOCATION

# Clean up template file
rm -f databricks-deployment.json
```

**Key Configurations:**
- **Premium SKU** - Required for VNet injection and private link
- **enableNoPublicIp** - No public IPs on cluster nodes
- **publicNetworkAccess=Disabled** - Blocks all public access
- **requiredNsgRules=NoAzureDatabricksRules** - For SCC mode

---

## Phase 5: Secure Cluster Connectivity

SCC enables secure communication between Databricks control plane and data plane.

```bash
# Get the backend subnet ID for reference
BACKEND_SUBNET_ID=$(az network vnet subnet show \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --name "snet-backend-private-endpoint" \
    --query id -o tsv)

echo "Backend subnet prepared for SCC: $BACKEND_SUBNET_ID"

# Verify workspace configuration
az databricks workspace show \
    --resource-group $RG_NAME \
    --name $WORKSPACE_NAME \
    --query "{PublicAccess:publicNetworkAccess, NoPublicIP:parameters.enableNoPublicIp.value}"
```

**How SCC Works:**
- Control plane initiates connection through Azure backbone
- No inbound connections from internet required
- All traffic stays within Microsoft network
- Automatically enabled with our configuration

---

## Phase 6: Frontend Private Endpoints

Create private endpoints for workspace UI and authentication.

### Get Workspace Resource ID

```bash
WORKSPACE_ID=$(az databricks workspace show \
    --resource-group $RG_NAME \
    --name $WORKSPACE_NAME \
    --query id -o tsv)
```

### Create UI/API Private Endpoint

```bash
az network private-endpoint create \
    --resource-group $RG_NAME \
    --name "pe-databricks-ui-api" \
    --vnet-name $VNET_NAME \
    --subnet "snet-private-endpoints" \
    --private-connection-resource-id $WORKSPACE_ID \
    --group-id "databricks_ui_api" \
    --connection-name "connection-databricks-ui-api" \
    --location $LOCATION
```

### Create Authentication Private Endpoint

```bash
az network private-endpoint create \
    --resource-group $RG_NAME \
    --name "pe-databricks-auth" \
    --vnet-name $VNET_NAME \
    --subnet "snet-private-endpoints" \
    --private-connection-resource-id $WORKSPACE_ID \
    --group-id "browser_authentication" \
    --connection-name "connection-databricks-auth" \
    --location $LOCATION
```

**Two Types of Frontend Endpoints:**
1. **databricks_ui_api** - Workspace UI access and REST API calls
2. **browser_authentication** - Azure AD authentication flows

---

## Phase 7: Backend Private Endpoint

Create backend private endpoint for SCC communication.

```bash
# This may be automatically created by Azure Databricks
az network private-endpoint create \
    --resource-group $RG_NAME \
    --name "pe-databricks-backend" \
    --vnet-name $VNET_NAME \
    --subnet "snet-backend-private-endpoint" \
    --private-connection-resource-id $WORKSPACE_ID \
    --group-id "databricks_ui_api" \
    --connection-name "connection-databricks-backend" \
    --location $LOCATION
```

**Purpose:**
- Allows control plane to manage compute resources
- Enables job submission and monitoring
- Provides secure channel for metadata operations

---

## Phase 8: Private DNS Configuration

Configure private DNS for name resolution within the VNet.

### Create Private DNS Zone

```bash
az network private-dns zone create \
    --resource-group $RG_NAME \
    --name "privatelink.azuredatabricks.net"
```

### Link DNS Zone to VNet

```bash
az network private-dns link vnet create \
    --resource-group $RG_NAME \
    --zone-name "privatelink.azuredatabricks.net" \
    --name "link-databricks-vnet" \
    --virtual-network $VNET_NAME \
    --registration-enabled false
```

### Configure DNS Records

```bash
# Get workspace URL
WORKSPACE_URL=$(az databricks workspace show \
    --resource-group $RG_NAME \
    --name $WORKSPACE_NAME \
    --query workspaceUrl -o tsv)

# Extract hostname
WORKSPACE_HOST="${WORKSPACE_URL%%.*}"

# Get private IPs
UI_API_PE_NIC_ID=$(az network private-endpoint show \
    --resource-group $RG_NAME \
    --name "pe-databricks-ui-api" \
    --query 'networkInterfaces[0].id' -o tsv)

UI_API_IP=$(az network nic show \
    --ids $UI_API_PE_NIC_ID \
    --query 'ipConfigurations[0].privateIPAddress' -o tsv)

AUTH_PE_NIC_ID=$(az network private-endpoint show \
    --resource-group $RG_NAME \
    --name "pe-databricks-auth" \
    --query 'networkInterfaces[0].id' -o tsv)

AUTH_IP=$(az network nic show \
    --ids $AUTH_PE_NIC_ID \
    --query 'ipConfigurations[0].privateIPAddress' -o tsv)

# Create DNS records
az network private-dns record-set a create \
    --resource-group $RG_NAME \
    --zone-name "privatelink.azuredatabricks.net" \
    --name "$WORKSPACE_HOST"

az network private-dns record-set a add-record \
    --resource-group $RG_NAME \
    --zone-name "privatelink.azuredatabricks.net" \
    --record-set-name "$WORKSPACE_HOST" \
    --ipv4-address $UI_API_IP

az network private-dns record-set a create \
    --resource-group $RG_NAME \
    --zone-name "privatelink.azuredatabricks.net" \
    --name "adb-auth-${WORKSPACE_HOST}"

az network private-dns record-set a add-record \
    --resource-group $RG_NAME \
    --zone-name "privatelink.azuredatabricks.net" \
    --record-set-name "adb-auth-${WORKSPACE_HOST}" \
    --ipv4-address $AUTH_IP
```

**How DNS Works:**
1. User accesses workspace URL
2. Private DNS zone resolves to private IP
3. Traffic flows through private endpoint

---

## Phase 9: Jump VM Creation

Create a VM within the VNet for accessing the private Databricks workspace.

### Try Multiple VM Sizes (for availability)

```bash
# Array of VM sizes to try
VM_SIZES=(
    "Standard_B2s"       # 2 vCPU, 4 GB RAM
    "Standard_B2ms"      # 2 vCPU, 8 GB RAM
    "Standard_D2s_v5"    # 2 vCPU, 8 GB RAM
    "Standard_D2s_v4"    # 2 vCPU, 8 GB RAM
    "Standard_D2s_v3"    # 2 vCPU, 8 GB RAM
)

VM_CREATED=false

for SIZE in "${VM_SIZES[@]}"; do
    echo "Attempting VM creation with size: $SIZE"
    
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
        --nsg ""; then
        
        VM_CREATED=true
        echo "Jump VM created successfully with size: $SIZE"
        break
    else
        echo "Size $SIZE not available, trying next..."
    fi
done
```

### Install Desktop Environment

```bash
# Install desktop for GUI access
az vm run-command invoke \
    --resource-group $RG_NAME \
    --name $VM_NAME \
    --command-id RunShellScript \
    --scripts "sudo apt-get update && sudo apt-get install -y ubuntu-desktop firefox xrdp && sudo systemctl enable xrdp"
```

**Purpose:**
- Provides access point within the private network
- Used for administrative tasks and testing
- No public IP (accessed via Bastion)

---

## Phase 10: Azure Bastion

Create secure RDP/SSH access to the Jump VM.

### Create Public IP for Bastion

```bash
az network public-ip create \
    --resource-group $RG_NAME \
    --name "pip-bastion" \
    --sku Standard \
    --location $LOCATION
```

### Create Bastion Host

```bash
az network bastion create \
    --name $BASTION_NAME \
    --public-ip-address "pip-bastion" \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --location $LOCATION
```

**Benefits:**
- No public IPs needed on VMs
- Protection against port scanning
- Azure AD integration
- HTML5 browser-based access

**Note:** This operation takes 5-10 minutes to complete.

---

## Phase 11: Validation

Verify all components are properly configured.

### Check Workspace Configuration

```bash
az databricks workspace show \
    --resource-group $RG_NAME \
    --name $WORKSPACE_NAME \
    --query "{Name:name, URL:workspaceUrl, Status:provisioningState, PublicAccess:publicNetworkAccess}"
```

### Check Private Endpoints

```bash
az network private-endpoint list \
    --resource-group $RG_NAME \
    --query "[].{Name:name, State:provisioningState, Connection:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}"
```

### Check Subnets

```bash
az network vnet subnet list \
    --resource-group $RG_NAME \
    --vnet-name $VNET_NAME \
    --query "[].{Name:name, AddressPrefix:addressPrefix, Delegation:delegations[0].serviceName}"
```

### Check DNS Records

```bash
az network private-dns record-set a list \
    --resource-group $RG_NAME \
    --zone-name "privatelink.azuredatabricks.net" \
    --query "[].{Name:name, IP:aRecords[0].ipv4Address}"
```

---

## Access Instructions

### 1. Wait for Bastion Deployment
Check status in Azure Portal (typically 5-10 minutes).

### 2. Access Jump VM via Bastion
1. Go to Azure Portal
2. Navigate to Resource Groups → `$RG_NAME` → `$VM_NAME`
3. Click "Connect" → Select "Bastion"
4. Enter credentials:
   - **Username:** `azureuser`
   - **Password:** `SecurePass@India2025!` (CHANGE THIS!)

### 3. Access Databricks from Jump VM
1. Open browser in Jump VM
2. Navigate to your workspace URL
3. Login with Azure AD credentials

### 4. Create Your First Cluster
1. Go to Compute in Databricks workspace
2. Click "Create Cluster"
3. Configure cluster settings (no public IP option should be selected)
4. Wait for cluster to start

---

## Cost Optimization

### Daily Operations
```bash
# Stop Jump VM when not in use
az vm deallocate --resource-group $RG_NAME --name $VM_NAME

# Start Jump VM when needed
az vm start --resource-group $RG_NAME --name $VM_NAME
```

### Monthly Savings
- **Stop VMs:** Save ~$50-100/month per VM
- **Delete Bastion:** Save ~$140/month (recreate when needed)
- **Use Spot instances:** Save 60-90% on compute costs
- **Auto-shutdown policies:** Automate cost savings

### Monitor Costs
```bash
# Check current month costs
az consumption usage list --start-date 2025-01-01 --end-date 2025-01-31
```

---

## Troubleshooting

### Cannot Access Databricks Workspace

**Check 1: Bastion Status**
```bash
az network bastion show \
    --resource-group $RG_NAME \
    --name $BASTION_NAME \
    --query "{Name:name, Status:provisioningState}"
```

**Check 2: VM Status**
```bash
az vm show \
    --resource-group $RG_NAME \
    --name $VM_NAME \
    --query "{Name:name, Status:powerState}"
```

**Check 3: Private Endpoint Connections**
```bash
az network private-endpoint show \
    --resource-group $RG_NAME \
    --name "pe-databricks-ui-api" \
    --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState"
```

**Check 4: DNS Resolution (from Jump VM)**
```bash
nslookup $WORKSPACE_URL
```

### Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| Bastion taking too long | Check Azure service health, wait up to 15 minutes |
| VM creation fails | Try different VM sizes or regions |
| DNS not resolving | Verify private DNS zone is linked to VNet |
| Workspace not accessible | Check private endpoint connection status |
| Cluster won't start | Verify subnet delegation and NSG rules |

### Complete Cleanup

```bash
# Delete everything
az group delete --name $RG_NAME --yes --no-wait

# This will delete:
# - All VMs, Bastion, Databricks workspace
# - All networking components
# - All storage accounts and managed resources
```

---

## Security Considerations

### ⚠️ IMPORTANT: Change Default Passwords
```bash
# Connect to Jump VM and change password
sudo passwd azureuser
```

### Additional Security Measures
1. **Enable Azure AD authentication** for Databricks
2. **Configure conditional access** policies
3. **Enable audit logging** for all resources
4. **Set up Azure Monitor** alerts
5. **Regular security reviews** of NSG rules

### Network Security Best Practices
- Review and customize NSG rules based on requirements
- Enable Azure Firewall for advanced threat protection
- Consider using Azure Private Link for additional services
- Implement network monitoring and logging

---

## Next Steps

1. **Configure Databricks Workspace Settings**
   - Set up users and groups
   - Configure cluster policies
   - Set up data sources and storage accounts

2. **Implement Data Pipeline**
   - Create notebooks for data processing
   - Set up scheduled jobs
   - Configure monitoring and alerting

3. **Security Hardening**
   - Implement Azure Policy for governance
   - Set up Azure Security Center
   - Configure backup and disaster recovery

---

*This deployment guide ensures a completely private Azure Databricks environment with enterprise-grade security and no public internet exposure.*