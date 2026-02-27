// Main orchestrator — deploys VNet-injected Databricks workspace with Private Link,
// VNet Data Gateway subnet, diagnostics, and defense-in-depth for secure Power BI connectivity

targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Prefix applied to all resource names')
param namePrefix string = 'dbw'

@description('VNet address space CIDR')
param vnetCidr string = '10.0.0.0/16'

@description('Host (public) subnet CIDR — at least /26')
param hostSubnetCidr string = '10.0.1.0/24'

@description('Container (private) subnet CIDR — at least /26')
param containerSubnetCidr string = '10.0.2.0/24'

@description('Private endpoint subnet CIDR')
param privateEndpointSubnetCidr string = '10.0.3.0/24'

@description('VNet Data Gateway delegated subnet CIDR')
param gatewaySubnetCidr string = '10.0.4.0/24'

@description('Management/jumpbox subnet CIDR')
param mgmtSubnetCidr string = '10.0.5.0/24'

@description('Admin username for the jumpbox VM')
param jumpboxAdminUsername string = 'rharrington'

@secure()
@description('Admin password for the jumpbox VM')
param jumpboxAdminPassword string

@description('Managed resource group name for Databricks-managed resources (leave empty for default)')
param managedResourceGroupName string = ''

// ─── NSGs (separate per subnet for least-privilege) ─────────────────────────

module nsg 'modules/nsg.bicep' = {
  name: 'nsg-deployment'
  params: {
    location: location
    namePrefix: namePrefix
  }
}

// ─── VNet, Subnets, NAT Gateway ─────────────────────────────────────────────

module vnet 'modules/vnet.bicep' = {
  name: 'vnet-deployment'
  params: {
    location: location
    namePrefix: namePrefix
    vnetCidr: vnetCidr
    hostSubnetCidr: hostSubnetCidr
    containerSubnetCidr: containerSubnetCidr
    privateEndpointSubnetCidr: privateEndpointSubnetCidr
    gatewaySubnetCidr: gatewaySubnetCidr
    mgmtSubnetCidr: mgmtSubnetCidr
    hostNsgId: nsg.outputs.hostNsgId
    containerNsgId: nsg.outputs.containerNsgId
    gatewayNsgId: nsg.outputs.gatewayNsgId
  }
}

// ─── Databricks Workspace (Private Link, public access disabled) ─────────────

module databricks 'modules/databricks.bicep' = {
  name: 'databricks-deployment'
  params: {
    location: location
    namePrefix: namePrefix
    vnetId: vnet.outputs.vnetId
    hostSubnetName: vnet.outputs.hostSubnetName
    containerSubnetName: vnet.outputs.containerSubnetName
    managedResourceGroupName: managedResourceGroupName
  }
}

// ─── Private Endpoints + DNS ─────────────────────────────────────────────────

module privateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'private-endpoint-deployment'
  params: {
    location: location
    namePrefix: namePrefix
    workspaceId: databricks.outputs.workspaceId
    peSubnetId: vnet.outputs.peSubnetId
    vnetId: vnet.outputs.vnetId
  }
}

// ─── Diagnostics (Log Analytics + audit logging) ─────────────────────────────

module diagnostics 'modules/diagnostics.bicep' = {
  name: 'diagnostics-deployment'
  params: {
    location: location
    namePrefix: namePrefix
    databricksWorkspaceName: '${namePrefix}-databricks-ws'
  }
  dependsOn: [
    databricks
  ]
}

// ─── Jumpbox VM (private access to workspace) ────────────────────────────────

module jumpbox 'modules/jumpbox.bicep' = {
  name: 'jumpbox-deployment'
  params: {
    location: location
    namePrefix: namePrefix
    mgmtSubnetId: vnet.outputs.mgmtSubnetId
    adminUsername: jumpboxAdminUsername
    adminPassword: jumpboxAdminPassword
  }
}

// ─── Outputs ────────────────────────────────────────────────────────────────

output workspaceUrl string = databricks.outputs.workspaceUrl
output workspaceId string = databricks.outputs.workspaceId
output vnetName string = vnet.outputs.vnetName
output natGatewayPublicIp string = vnet.outputs.natGatewayPublicIp
output logAnalyticsWorkspaceId string = diagnostics.outputs.logAnalyticsWorkspaceId
output jumpboxPrivateIp string = jumpbox.outputs.privateIp
