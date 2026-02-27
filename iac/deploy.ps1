<#
.SYNOPSIS
    Deploys the secure VNet-injected Databricks workspace with Private Link,
    VNet Data Gateway subnet, and diagnostics.

.DESCRIPTION
    Creates the resource group (if it doesn't exist), validates the Bicep template,
    and deploys all resources. Supports overriding defaults via parameters.

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -ResourceGroupName "my-rg" -Location "westus2" -NamePrefix "mydbw"
#>

param(
    [string]$ResourceGroupName = "adb-private-rg",
    [string]$Location = "eastus2",
    [string]$NamePrefix = "dbw",
    [string]$VnetCidr = "10.0.0.0/16",
    [string]$HostSubnetCidr = "10.0.1.0/24",
    [string]$ContainerSubnetCidr = "10.0.2.0/24",
    [string]$PrivateEndpointSubnetCidr = "10.0.3.0/24",
    [string]$GatewaySubnetCidr = "10.0.4.0/24",
    [string]$MgmtSubnetCidr = "10.0.5.0/24",
    [string]$JumpboxAdminUsername = "rharrington",
    [string]$ManagedResourceGroupName = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Databricks VNet-Injected Deployment"     -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ─── Pre-flight: verify az CLI is logged in ──────────────────────────────────

Write-Host "`n[1/4] Checking Azure CLI login..." -ForegroundColor Yellow
$account = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
}
$sub = ($account | ConvertFrom-Json)
Write-Host "  Subscription: $($sub.name) ($($sub.id))" -ForegroundColor Green

# ─── Prompt for jumpbox password if not provided ─────────────────────────────

Write-Host "`n[1.5/4] Jumpbox VM credentials..." -ForegroundColor Yellow
$securePassword = Read-Host -Prompt "  Enter admin password for jumpbox VM ($JumpboxAdminUsername)" -AsSecureString
$plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))

# ─── Create resource group if it doesn't exist ──────────────────────────────

Write-Host "`n[2/4] Ensuring resource group '$ResourceGroupName' exists..." -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroupName 2>&1
if ($rgExists -eq "false") {
    Write-Host "  Creating resource group..." -ForegroundColor Gray
    az group create --name $ResourceGroupName --location $Location --output none
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create resource group."; exit 1 }
    Write-Host "  Resource group created." -ForegroundColor Green
} else {
    Write-Host "  Resource group already exists." -ForegroundColor Green
}

# ─── Validate the Bicep template ────────────────────────────────────────────

Write-Host "`n[3/4] Validating Bicep template..." -ForegroundColor Yellow
$validateResult = az deployment group validate `
    --resource-group $ResourceGroupName `
    --template-file "$scriptDir\main.bicep" `
    --parameters `
        location=$Location `
        namePrefix=$NamePrefix `
        vnetCidr=$VnetCidr `
        hostSubnetCidr=$HostSubnetCidr `
        containerSubnetCidr=$ContainerSubnetCidr `
        privateEndpointSubnetCidr=$PrivateEndpointSubnetCidr `
        gatewaySubnetCidr=$GatewaySubnetCidr `
        mgmtSubnetCidr=$MgmtSubnetCidr `
        jumpboxAdminUsername=$JumpboxAdminUsername `
        jumpboxAdminPassword=$plainPassword `
        managedResourceGroupName=$ManagedResourceGroupName `
    2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Template validation failed:`n$validateResult"
    exit 1
}
Write-Host "  Validation passed." -ForegroundColor Green

# ─── Deploy ─────────────────────────────────────────────────────────────────

Write-Host "`n[4/4] Deploying resources (this may take 5-10 minutes)..." -ForegroundColor Yellow
$deployOutput = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file "$scriptDir\main.bicep" `
    --parameters `
        location=$Location `
        namePrefix=$NamePrefix `
        vnetCidr=$VnetCidr `
        hostSubnetCidr=$HostSubnetCidr `
        containerSubnetCidr=$ContainerSubnetCidr `
        privateEndpointSubnetCidr=$PrivateEndpointSubnetCidr `
        gatewaySubnetCidr=$GatewaySubnetCidr `
        mgmtSubnetCidr=$MgmtSubnetCidr `
        jumpboxAdminUsername=$JumpboxAdminUsername `
        jumpboxAdminPassword=$plainPassword `
        managedResourceGroupName=$ManagedResourceGroupName `
    --output json `
    2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed:`n$deployOutput"
    exit 1
}

$outputs = ($deployOutput | ConvertFrom-Json).properties.outputs

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Workspace URL:      https://$($outputs.workspaceUrl.value)" -ForegroundColor White
Write-Host "  Workspace ID:       $($outputs.workspaceId.value)" -ForegroundColor White
Write-Host "  VNet Name:          $($outputs.vnetName.value)" -ForegroundColor White
Write-Host "  NAT Gateway IP:     $($outputs.natGatewayPublicIp.value)" -ForegroundColor White
Write-Host "  Log Analytics:      $($outputs.logAnalyticsWorkspaceId.value)" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps (manual):" -ForegroundColor Gray
Write-Host "    1. Register a VNet Data Gateway in Power BI Admin Portal" -ForegroundColor Gray
Write-Host "       (use the gateway subnet: $GatewaySubnetCidr)" -ForegroundColor Gray
Write-Host "    2. Create a Service Principal in Entra ID" -ForegroundColor Gray
Write-Host "    3. Add the SPN to Databricks and generate an OAuth secret" -ForegroundColor Gray
Write-Host "    4. Configure Unity Catalog grants (GRANT SELECT on tables)" -ForegroundColor Gray
Write-Host "    5. Configure Power BI connection with M2M OAuth" -ForegroundColor Gray
Write-Host ""
