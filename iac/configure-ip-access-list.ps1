<#
.SYNOPSIS
    Adds Power BI service tag CIDRs to a Databricks workspace IP access list.

.DESCRIPTION
    Uses the Databricks REST API to add Power BI service tag IPs for a
    specified Azure region, along with the NAT Gateway IP, to the workspace's
    IP access list. Existing access list entries are preserved — this script
    only adds new entries.
    Use -Action Disable to turn off IP access lists entirely.

.EXAMPLE
    .\configure-ip-access-list.ps1 -Region WestUS
    .\configure-ip-access-list.ps1 -Region EastUS2
    .\configure-ip-access-list.ps1 -Action Disable
#>

param(
    [ValidateSet("Enable", "Disable")]
    [string]$Action = "Enable",

    [string]$ResourceGroupName = "adb-private-rg",
    [string]$WorkspaceName = "dbw-databricks-ws",
    [string]$NatPipName = "dbw-nat-pip",

    [ValidateSet("WestUS", "WestUS2", "WestUS3", "EastUS", "EastUS2", "CentralUS", "NorthCentralUS", "SouthCentralUS", "WestCentralUS")]
    [string]$Region = "WestUS3"
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

# Fetch Power BI service tag IPs
Write-Host "  Fetching PowerBI.$Region service tag IPs..." -ForegroundColor Yellow
$azureLocation = $Region.ToLower()
$tagsJson = az network list-service-tags --location $azureLocation -o json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to fetch Azure service tags.`n$tagsJson"
    exit 1
}
$allTags = $tagsJson | ConvertFrom-Json
$pbiTag = $allTags.values | Where-Object { $_.name -eq "PowerBI.$Region" }
if (-not $pbiTag) {
    Write-Error "Service tag 'PowerBI.$Region' not found. Run 'az network list-service-tags --location $azureLocation' to see available regions."
    exit 1
}
# Filter to IPv4 only — Databricks IP access lists don't support IPv6
$pbiIps = $pbiTag.properties.addressPrefixes | Where-Object { $_ -notmatch ':' }
Write-Host "  Found $($pbiIps.Count) IPv4 ranges for PowerBI.$Region" -ForegroundColor Green

# Build the IP list
$ipList = [System.Collections.Generic.List[string]]::new()
$ipList.Add("$natIp/32")
foreach ($ip in $pbiIps) { $ipList.Add($ip) }

$uniqueIps = $ipList | Sort-Object -Unique
Write-Host "  Allow list ($($uniqueIps.Count) entries):" -ForegroundColor White
foreach ($ip in $uniqueIps) { Write-Host "    $ip" -ForegroundColor Gray }

# Add the allow list (preserves existing lists)
Write-Host "`n[4/4] Configuring IP access lists..." -ForegroundColor Yellow

# Create the allow list
$createBody = @{
    label        = "PowerBI.$Region"
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
Write-Host " Power BI Service (PowerBI.$Region) is ALLOWED." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "To disable IP access lists:" -ForegroundColor White
Write-Host "  .\configure-ip-access-list.ps1 -Action Disable" -ForegroundColor Gray
