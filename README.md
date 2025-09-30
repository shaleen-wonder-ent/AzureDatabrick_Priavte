# Azure Databricks Private Network Deployment with ADLS Gen2

[![Azure](https://img.shields.io/badge/Azure-0078D4?style=for-the-badge&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com/)
[![Databricks](https://img.shields.io/badge/Databricks-FF3621?style=for-the-badge&logo=databricks&logoColor=white)](https://databricks.com/)
[![ADLS Gen2](https://img.shields.io/badge/ADLS_Gen2-0078D4?style=for-the-badge&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com/)
[![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)

A comprehensive solution for deploying Azure Databricks in a completely private network environment with **Secure Cluster Connectivity (SCC)** and **ADLS Gen2 integration** in the **Central India** region.

## 🚀 Quick Start

This repository provides both automated and manual deployment options for setting up a production-ready, enterprise-grade Azure Databricks environment with zero public internet exposure.

### ⚡ Automated Deployment (Recommended)

```bash
# Clone the repository
git clone https://github.com/shaleen-wonder-ent/AzDatabricks_Private_deployment.git
cd AzDatabricks_Private_deployment

# Make the script executable
chmod +x setup-databricks-centralindia-complete-documented.sh

# Run the automated deployment
./setup-databricks-centralindia-complete-documented.sh
```

### 📖 Manual Step-by-Step Deployment

For detailed manual instructions, see our comprehensive [Setup Guide](./setup.md).

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    AZURE CENTRAL INDIA                       │
│  ┌─────────────────────────────────────────────────────┐    │
│  │            VIRTUAL NETWORK (10.0.0.0/16)            │    │
│  │                                                     │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │    │
│  │  │ Databricks  │  │ ADLS Gen2   │  │ Private     │ │    │
│  │  │ Subnets     │  │ Storage     │  │ Endpoints   │ │    │
│  │  │             │  │ • Blob PE   │  │ • DB UI/API │ │    │
│  │  │             │  │ • DFS PE    │  │ • Auth      │ │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │    │
│  │                                                     │    │
│  │  ┌─────────────┐  ┌─────────────┐                  │    │
│  │  │ Jump VM     │  │ Azure       │                  │    │
│  │  │ & Bastion   │  │ Bastion     │                  │    │
│  │  └─────────────┘  └─────────────┘                  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## 🔒 Security Features

- ✅ **Zero Public IPs** - No compute resources exposed to internet
- ✅ **Private Endpoints** - All connectivity through Azure backbone
- ✅ **Secure Cluster Connectivity (SCC)** - Control plane communication
- ✅ **Network Isolation** - Comprehensive NSG and subnet segmentation
- ✅ **Azure Bastion** - Secure RDP/SSH access without public IPs
- ✅ **Private DNS** - Internal name resolution only
- ✅ **ADLS Gen2 Private Access** - Storage firewall with private endpoints only
- ✅ **Service Principal Authentication** - Secure storage access from Databricks
- ✅ **Hierarchical Namespace** - POSIX-compliant file system operations

## 💾 ADLS Gen2 Data Lake Features

### 📁 Pre-configured Containers
Following data lake best practices with organized storage structure:

| Container | Purpose | Use Case |
|-----------|---------|----------|
| **raw** | Landing zone | Ingested data in original format |
| **processed** | Cleaned data | Transformed and validated datasets |
| **curated** | Business-ready | Aggregated data for analytics |
| **sandbox** | Experimentation | Development and testing workspace |
| **archive** | Long-term storage | Historical data retention |

### 🔐 Security & Access
- **Private Endpoints**: Blob and DFS endpoints for secure access
- **Firewall Rules**: Public access disabled, VNet access only
- **Service Principal**: Automated authentication from Databricks
- **RBAC Integration**: Azure AD-based access control

### ⚡ Performance Optimizations
- **Hierarchical Namespace**: Faster file operations
- **Hot Storage Tier**: Optimized for frequent access
- **Zone Redundancy**: High availability within region
- **Auto-mounted**: Ready-to-use mounts in Databricks

## 📦 What Gets Deployed

| Component | Purpose | Configuration |
|-----------|---------|---------------|
| **Resource Group** | Logical container | `rg-databricks-private-india` |
| **Virtual Network** | Network foundation | `10.0.0.0/16` address space |
| **Databricks Workspace** | Analytics platform | Premium SKU, private access only |
| **ADLS Gen2 Storage** | Data lake storage | Hierarchical namespace, private access |
| **Storage Containers** | Data organization | raw, processed, curated, sandbox, archive |
| **Private Endpoints** | Secure connectivity | DB UI/API, Auth, Storage Blob & DFS |
| **Service Principal** | Storage authentication | Databricks to ADLS access |
| **Jump VM** | Access point | Ubuntu with desktop environment |
| **Azure Bastion** | Secure gateway | Browser-based RDP/SSH |
| **Private DNS Zones** | Name resolution | Databricks and Storage endpoints |

## 🎯 Prerequisites

- **Azure CLI** (v2.0+) with Databricks extension
- **Azure Subscription** with Contributor/Owner role
- **Sufficient quota** in Central India region
- **Basic understanding** of Azure networking concepts

## 📋 Deployment Steps

1. **Clone Repository**
   ```bash
   git clone https://github.com/shaleen-wonder-ent/AzDatabricks_Private_deployment.git
   ```

2. **Review Configuration**
   - Edit variables in the script or setup.md
   - Ensure no IP conflicts with existing networks

3. **Execute Deployment**
   - Automated: Run the shell script
   - Manual: Follow [setup.md](./setup.md) guide

4. **Access Environment**
   - Connect to Jump VM via Azure Bastion
   - Access Databricks workspace from Jump VM
   - Use pre-configured ADLS Gen2 storage mounts

## 💾 ADLS Gen2 Usage Examples

Once deployed, your Databricks workspace will have pre-configured access to ADLS Gen2:

### Python Examples
```python
# Read data from raw container
df = spark.read.parquet("/mnt/raw/sample-data/")

# Process and write to processed container
processed_df = df.filter(df.status == "active")
processed_df.write.parquet("/mnt/processed/cleaned-data/")

# Create curated dataset
curated_df = processed_df.groupBy("category").count()
curated_df.write.parquet("/mnt/curated/category-summary/")
```

### Scala Examples
```scala
// Read from ADLS Gen2
val df = spark.read.parquet("/mnt/raw/sample-data/")

// Write to processed layer
df.filter($"status" === "active")
  .write
  .mode("overwrite")
  .parquet("/mnt/processed/cleaned-data/")
```

### SQL Examples
```sql
-- Create table pointing to ADLS Gen2
CREATE TABLE raw_data
USING PARQUET
LOCATION '/mnt/raw/sample-data/'

-- Query data across containers
SELECT category, COUNT(*) as count
FROM raw_data
WHERE status = 'active'
GROUP BY category
```

## 🔧 Configuration

### Environment Variables

Customize these variables before deployment:

```bash
export LOCATION="centralindia"
export RG_NAME="rg-databricks-private-india"
export VNET_NAME="vnet-databricks-india"
export WORKSPACE_NAME="dbw-private-india-$(date +%s)"
export STORAGE_ACCOUNT_NAME="adls$(date +%s)"  # ADLS Gen2 account
export VM_ADMIN_PASSWORD="YourSecurePassword123!"  # CHANGE THIS!
```

### Network Configuration

| Subnet | CIDR | Purpose |
|--------|------|----------|
| Host | `10.0.1.0/24` | Databricks driver nodes |
| Container | `10.0.2.0/24` | Databricks executor nodes |
| Private Endpoints | `10.0.3.0/24` | Frontend connectivity |
| Backend PE | `10.0.4.0/24` | SCC communication |
| Storage PE | `10.0.7.0/24` | ADLS Gen2 private endpoints |
| Jump VM | `10.0.5.0/24` | Administrative access |
| Bastion | `10.0.6.0/26` | Secure gateway |

## 💰 Cost Optimization

### Daily Operations
```bash
# Stop Jump VM when not in use (saves ~$2-5/day)
az vm deallocate --resource-group rg-databricks-private-india --name vm-jumpbox-india

# Start when needed
az vm start --resource-group rg-databricks-private-india --name vm-jumpbox-india
```

### Monthly Savings
- **Deallocate VMs:** ~$50-100/month
- **Use Spot instances:** 60-90% savings
- **Delete Bastion when not needed:** ~$140/month
- **ADLS Gen2 Lifecycle Management:** Archive old data automatically
- **Storage Tier Optimization:** Move to cool/archive tiers

## 🛠️ Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| **Bastion deployment slow** | Wait 10-15 minutes, check Azure service health |
| **VM creation fails** | Try different VM sizes or use Spot instances |
| **DNS not resolving** | Verify private DNS zone VNet link |
| **Workspace inaccessible** | Check private endpoint connection status |

### Validation Commands

```bash
# Check workspace status
az databricks workspace show --resource-group $RG_NAME --name $WORKSPACE_NAME

# Verify private endpoints
az network private-endpoint list --resource-group $RG_NAME

# Check ADLS Gen2 storage account
az storage account show --resource-group $RG_NAME --name $STORAGE_ACCOUNT_NAME

# Verify storage containers
az storage container list --account-name $STORAGE_ACCOUNT_NAME --auth-mode login

# Test DNS resolution (from Jump VM)
nslookup your-workspace-url.azuredatabricks.net
nslookup your-storage-account.blob.core.windows.net
nslookup your-storage-account.dfs.core.windows.net
```

## 📚 Documentation

- 📖 **[Complete Setup Guide](./setup.md)** - Detailed step-by-step instructions
- 🔧 **[Automated Script](./setup-databricks-centralindia-complete-documented.sh)** - One-click deployment
- 🛡️ **Security Best Practices** - Included in setup guide
- 💡 **Cost Optimization Tips** - Reduce monthly expenses

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Important Notes

- **Change default passwords** immediately after deployment
- **Review security settings** based on your requirements
- **Monitor costs** regularly using Azure Cost Management
- **This creates real Azure resources** that incur charges

## 🆘 Support

- 📧 **Issues:** [GitHub Issues](https://github.com/shaleen-wonder-ent/AzDatabricks_Private_deployment/issues)
- 📖 **Documentation:** [Setup Guide](./setup.md)
- 💬 **Discussions:** [GitHub Discussions](https://github.com/shaleen-wonder-ent/AzDatabricks_Private_deployment/discussions)

## 🌟 Features

### ✨ What Makes This Special

- **🎯 Zero Configuration** - Works out of the box with ADLS Gen2 integration
- **🔒 Maximum Security** - Enterprise-grade private networking for compute and storage
- **📍 India Optimized** - Specifically configured for Central India region
- **💾 Data Lake Ready** - Pre-configured ADLS Gen2 with best practice containers
- **🔐 Secure Storage** - Service principal authentication with private endpoints
- **💰 Cost Aware** - Built-in cost optimization features
- **📚 Well Documented** - Comprehensive guides and troubleshooting
- **🚀 Production Ready** - Tested and validated configuration

### 🔄 Deployment Options

1. **🤖 Automated Script** - One command deployment
2. **👨‍💻 Manual Steps** - Educational step-by-step guide
3. **🔧 Customizable** - Easy to modify for specific requirements

---

**Made with ❤️ for the Azure Databricks community in India** 🇮🇳

*Deploy with confidence. Scale with security.*