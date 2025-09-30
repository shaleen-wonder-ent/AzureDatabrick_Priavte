# Azure Databricks Private Network Deployment

[![Azure](https://img.shields.io/badge/Azure-0078D4?style=for-the-badge&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com/)
[![Databricks](https://img.shields.io/badge/Databricks-FF3621?style=for-the-badge&logo=databricks&logoColor=white)](https://databricks.com/)
[![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)

A comprehensive solution for deploying Azure Databricks in a completely private network environment with **Secure Cluster Connectivity (SCC)** in the **Central India** region.

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
│  │  │ Databricks  │  │ Private     │  │ Jump VM     │ │    │
│  │  │ Subnets     │  │ Endpoints   │  │ & Bastion   │ │    │
│  │  │             │  │             │  │             │ │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │    │
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

## 📦 What Gets Deployed

| Component | Purpose | Configuration |
|-----------|---------|---------------|
| **Resource Group** | Logical container | `rg-databricks-private-india` |
| **Virtual Network** | Network foundation | `10.0.0.0/16` address space |
| **Databricks Workspace** | Analytics platform | Premium SKU, private access only |
| **Private Endpoints** | Secure connectivity | UI/API and Auth endpoints |
| **Jump VM** | Access point | Ubuntu with desktop environment |
| **Azure Bastion** | Secure gateway | Browser-based RDP/SSH |
| **Private DNS Zone** | Name resolution | `privatelink.azuredatabricks.net` |

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

## 🔧 Configuration

### Environment Variables

Customize these variables before deployment:

```bash
export LOCATION="centralindia"
export RG_NAME="rg-databricks-private-india"
export VNET_NAME="vnet-databricks-india"
export WORKSPACE_NAME="dbw-private-india-$(date +%s)"
export VM_ADMIN_PASSWORD="YourSecurePassword123!"  # CHANGE THIS!
```

### Network Configuration

| Subnet | CIDR | Purpose |
|--------|------|---------|
| Host | `10.0.1.0/24` | Databricks driver nodes |
| Container | `10.0.2.0/24` | Databricks executor nodes |
| Private Endpoints | `10.0.3.0/24` | Frontend connectivity |
| Backend PE | `10.0.4.0/24` | SCC communication |
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

# Test DNS resolution (from Jump VM)
nslookup your-workspace-url.azuredatabricks.net
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

- **🎯 Zero Configuration** - Works out of the box
- **🔒 Maximum Security** - Enterprise-grade private networking
- **📍 India Optimized** - Specifically configured for Central India region
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