# Azure Databricks + ADLS Gen2 Deployment Script for PowerShell
# This script can be run from Windows PowerShell/PowerShell Core

param(
    [string]$ResourceGroupName = "rg-databricks-private-india",
    [string]$Location = "centralindia",
    [string]$WorkspaceName = "dbw-private-india-$((Get-Date).Ticks)",
    [string]$StorageAccountName = "adls$((Get-Date).Ticks)",
    [securestring]$VMAdminPassword
)

# Colors for output
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Cyan"
$Red = "Red"

Write-Host "🚀 Azure Databricks + ADLS Gen2 Deployment" -ForegroundColor $Blue
Write-Host "=============================================" -ForegroundColor $Blue

# Check if Azure CLI is installed
try {
    az --version | Out-Null
    Write-Host "✓ Azure CLI is installed" -ForegroundColor $Green
} catch {
    Write-Host "✗ Azure CLI is not installed. Please install it first:" -ForegroundColor $Red
    Write-Host "https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" -ForegroundColor $Yellow
    exit 1
}

# Check if logged in
try {
    $account = az account show | ConvertFrom-Json
    Write-Host "✓ Logged in to Azure subscription: $($account.name)" -ForegroundColor $Green
} catch {
    Write-Host "✗ Not logged in to Azure. Please run 'az login' first" -ForegroundColor $Red
    exit 1
}

# Get VM password if not provided
if (-not $VMAdminPassword) {
    $VMAdminPassword = Read-Host "Enter password for Jump VM admin user" -AsSecureString
}

# Convert secure string to plain text for Azure CLI
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($VMAdminPassword)
$PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

Write-Host "Creating resource group..." -ForegroundColor $Blue
az group create --name $ResourceGroupName --location $Location

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Resource group created successfully" -ForegroundColor $Green
} else {
    Write-Host "✗ Failed to create resource group" -ForegroundColor $Red
    exit 1
}

# Deploy using ARM template
$deploymentName = "databricks-deployment-$((Get-Date).Ticks)"
Write-Host "Deploying infrastructure (this may take 15-20 minutes)..." -ForegroundColor $Blue

az deployment group create `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --template-file "azure-deploy.json" `
    --parameters workspaceName=$WorkspaceName storageAccountName=$StorageAccountName vmAdminPassword=$PlainPassword

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Basic infrastructure deployed successfully!" -ForegroundColor $Green
    Write-Host ""
    Write-Host "Deployment Summary:" -ForegroundColor $Blue
    Write-Host "- Resource Group: $ResourceGroupName" -ForegroundColor $Yellow
    Write-Host "- Databricks Workspace: $WorkspaceName" -ForegroundColor $Yellow
    Write-Host "- ADLS Gen2 Storage: $StorageAccountName" -ForegroundColor $Yellow
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor $Blue
    Write-Host "1. Run the full bash script for complete private endpoint setup" -ForegroundColor $Yellow
    Write-Host "2. Or continue with manual configuration using the setup.md guide" -ForegroundColor $Yellow
    Write-Host ""
    Write-Host "For complete setup, use WSL or Git Bash to run:" -ForegroundColor $Green
    Write-Host "./scripts/setup-databricks-centralindia-complete-documented.sh" -ForegroundColor $Green
} else {
    Write-Host "✗ Deployment failed. Check the error messages above." -ForegroundColor $Red
}

# Clear the password from memory
$PlainPassword = $null
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)