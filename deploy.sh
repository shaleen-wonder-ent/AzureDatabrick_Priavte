#!/bin/bash

#############################################
# Azure Databricks Private Network Deployment
# Quick Deploy Script - Central India Edition
#
# This script provides a simple wrapper to execute the
# main deployment script with proper configuration.
#
# Usage:
#   ./deploy.sh
#
# Prerequisites:
#   - Azure CLI installed and logged in
#   - Databricks extension installed
#   - Contributor/Owner permissions on Azure subscription
#############################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_header() {
    echo ""
    echo "========================================="
    echo "$1"
    echo "========================================="
}

# Display banner
cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║          Azure Databricks Private Network Deployment        ║
║                     Central India Edition                   ║
╚══════════════════════════════════════════════════════════════╝
EOF

print_header "Azure Databricks Private Deployment - Quick Start"

# Check if main script exists
MAIN_SCRIPT="./scripts/setup-databricks-centralindia-complete-documented.sh"

if [ ! -f "$MAIN_SCRIPT" ]; then
    print_error "Main deployment script not found at: $MAIN_SCRIPT"
    print_info "Please ensure the script exists in the scripts directory"
    exit 1
fi

print_status "Found main deployment script"

# Check prerequisites
print_info "Checking prerequisites..."

# Check Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed"
    print_info "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
print_status "Azure CLI is installed"

# Check Azure login
if ! az account show &> /dev/null; then
    print_error "Not logged into Azure. Please run 'az login'"
    exit 1
fi
print_status "Azure authentication verified"

# Get subscription info
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
print_info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Confirmation prompt
echo ""
print_warning "This deployment will create Azure resources that incur costs!"
print_info "The deployment includes:"
echo "  • Azure Databricks Workspace (Premium SKU)"
echo "  • Virtual Network with multiple subnets"
echo "  • Private Endpoints"
echo "  • Virtual Machine (Jump VM)"
echo "  • Azure Bastion"
echo "  • Storage accounts and other supporting resources"
echo ""

read -p "Do you want to continue with the deployment? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Deployment cancelled by user"
    exit 0
fi

# Make script executable
print_status "Making deployment script executable..."
chmod +x "$MAIN_SCRIPT"

# Execute the main deployment script
print_header "Starting Azure Databricks Private Network Deployment"
print_info "This process typically takes 15-20 minutes..."
print_warning "Please do not interrupt the deployment process"

echo ""
exec "$MAIN_SCRIPT"