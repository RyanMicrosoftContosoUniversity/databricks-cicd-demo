<#
.SYNOPSIS
    Enables or disables Databricks workspace IP access lists to control Power BI connectivity.

.DESCRIPTION
    Uses the Databricks REST API to toggle IP access lists on the workspace.
    When enabled, only the NAT Gateway IP (for cluster connectivity) and your
    current public IP are allowed. Use -IncludePowerBI to also allow Power BI
    Service IPs from the specified Azure region.
    When disabled, all IPs are allowed again.

.EXAMPLE
    .\configure-ip-access-list.ps1 -Action Enable
    .\configure-ip-access-list.ps1 -Action Disable
    .\configure-ip-access-list.ps1 -Action Enable -IncludePowerBI
    .\configure-ip-access-list.ps1 -Action Enable -IncludePowerBI -PowerBIRegion "EastUS2"
    .\configure-ip-access-list.ps1 -Action Enable -AllowedIps @("203.0.113.0/24")
#>

param(
    [ValidateSet("Enable", "Disable")]
    [string]$Action = "Enable",

    [string]$ResourceGroupName = "adb-private-rg",
    [string]$WorkspaceName = "dbw-databricks-ws",
    [string]$NatPipName = "dbw-nat-pip",

    [switch]$IncludePowerBI,
    [string]$PowerBIRegion = "WestUS3",
    [string]$AzureLocation = "eastus2",

    [string[]]$AllowedIps = @()
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Databricks IP Access List — $Action"    -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ─── Get Databricks AAD token via Azure CLI ──────────────────────────────────

Write-Host "`n[1/4] Acquiring Databricks access token..." -ForegroundColor Yellow
$tokenResponse = az account get-access-token --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get Databricks token. Ensure you are logged in with 'az login'."
    exit 1
}
$token = ($tokenResponse | ConvertFrom-Json).accessToken
Write-Host "  Token acquired." -ForegroundColor Green

# ─── Get workspace URL ───────────────────────────────────────────────────────

Write-Host "`n[2/4] Resolving workspace URL..." -ForegroundColor Yellow
$wsJson = az databricks workspace show `
    --resource-group $ResourceGroupName `
    --name $WorkspaceName `
    --query "workspaceUrl" -o tsv 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get workspace URL. Check resource group and workspace name.`n$wsJson"
    exit 1
}
$workspaceUrl = "https://$wsJson"
Write-Host "  Workspace: $workspaceUrl" -ForegroundColor Green

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

# ─── Disable path — just flip the feature flag ──────────────────────────────

if ($Action -eq "Disable") {
    Write-Host "`n[3/4] Disabling IP access lists..." -ForegroundColor Yellow
    $body = '{"enableIpAccessLists": "false"}'
    Invoke-RestMethod -Uri "$workspaceUrl/api/2.0/workspace-conf" `
        -Method Patch -Headers $headers -Body $body | Out-Null
    Write-Host "  IP access lists disabled — all IPs can now connect." -ForegroundColor Green

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " Done! Power BI can now reach the workspace." -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    exit 0
}

# ─── Enable path — resolve IPs, create allow list, enable feature ────────────

# Resolve NAT Gateway public IP (critical — clusters need this)
Write-Host "`n[3/4] Resolving IPs for allow list..." -ForegroundColor Yellow
$natIp = az network public-ip show `
    --resource-group $ResourceGroupName `
    --name $NatPipName `
    --query "ipAddress" -o tsv 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to resolve NAT Gateway public IP.`n$natIp"
    exit 1
}
Write-Host "  NAT Gateway IP: $natIp" -ForegroundColor Gray

# Detect current public IP (so the caller doesn't lock themselves out)
try {
    $myIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
    Write-Host "  Your public IP:  $myIp" -ForegroundColor Gray
} catch {
    Write-Warning "Could not detect your public IP. You may lock yourself out!"
    $myIp = $null
}

# Fetch Power BI service tag IPs if requested
$pbiIps = @()
if ($IncludePowerBI) {
    Write-Host "  Fetching PowerBI.$PowerBIRegion service tag IPs..." -ForegroundColor Yellow
    $tagsJson = az network list-service-tags --location $AzureLocation -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to fetch Azure service tags.`n$tagsJson"
        exit 1
    }
    $allTags = $tagsJson | ConvertFrom-Json
    $pbiTag = $allTags.values | Where-Object { $_.name -eq "PowerBI.$PowerBIRegion" }
    if (-not $pbiTag) {
        Write-Error "Service tag 'PowerBI.$PowerBIRegion' not found. Run 'az network list-service-tags --location $AzureLocation' to see available regions."
        exit 1
    }
    # Filter to IPv4 only — Databricks IP access lists don't support IPv6
    $pbiIps = $pbiTag.properties.addressPrefixes | Where-Object { $_ -notmatch ':' }
    Write-Host "  Found $($pbiIps.Count) IPv4 ranges for PowerBI.$PowerBIRegion" -ForegroundColor Green
}

# Build the IP list
$ipList = [System.Collections.Generic.List[string]]::new()
$ipList.Add("$natIp/32")
if ($myIp) { $ipList.Add("$myIp/32") }
foreach ($ip in $AllowedIps) { $ipList.Add($ip) }
foreach ($ip in $pbiIps) { $ipList.Add($ip) }

$uniqueIps = $ipList | Sort-Object -Unique
Write-Host "  Allow list ($($uniqueIps.Count) entries):" -ForegroundColor White
foreach ($ip in $uniqueIps) { Write-Host "    $ip" -ForegroundColor Gray }

# Delete any existing IP access lists to start clean
Write-Host "`n[4/4] Configuring IP access lists..." -ForegroundColor Yellow
$existing = Invoke-RestMethod -Uri "$workspaceUrl/api/2.0/ip-access-lists" `
    -Method Get -Headers $headers
if ($existing.ip_access_lists) {
    foreach ($list in $existing.ip_access_lists) {
        Write-Host "  Removing existing list: $($list.label) ($($list.list_id))" -ForegroundColor Gray
        Invoke-RestMethod -Uri "$workspaceUrl/api/2.0/ip-access-lists/$($list.list_id)" `
            -Method Delete -Headers $headers | Out-Null
    }
}

# Create the allow list
$createBody = @{
    label        = "Approved Networks"
    list_type    = "ALLOW"
    ip_addresses = @($uniqueIps)
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Uri "$workspaceUrl/api/2.0/ip-access-lists" `
    -Method Post -Headers $headers -Body $createBody | Out-Null
Write-Host "  Allow list created." -ForegroundColor Green

# Enable the feature
$enableBody = '{"enableIpAccessLists": "true"}'
Invoke-RestMethod -Uri "$workspaceUrl/api/2.0/workspace-conf" `
    -Method Patch -Headers $headers -Body $enableBody | Out-Null
Write-Host "  IP access lists enabled." -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Done! Only approved IPs can connect."    -ForegroundColor Green
if ($IncludePowerBI) {
    Write-Host " Power BI Service (PowerBI.$PowerBIRegion) is ALLOWED." -ForegroundColor Green
} else {
    Write-Host " Power BI Service is now BLOCKED."         -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
if (-not $IncludePowerBI) {
    Write-Host "To allow Power BI:" -ForegroundColor White
    Write-Host "  .\configure-ip-access-list.ps1 -Action Enable -IncludePowerBI" -ForegroundColor Gray
}
Write-Host "To allow all IPs:" -ForegroundColor White
Write-Host "  .\configure-ip-access-list.ps1 -Action Disable" -ForegroundColor Gray
