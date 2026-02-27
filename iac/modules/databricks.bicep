// Databricks workspace module — Premium tier, VNet-injected, Secure Cluster Connectivity

@description('Azure region')
param location string

@description('Prefix for resource names')
param namePrefix string

@description('Resource ID of the VNet')
param vnetId string

@description('Name of the host (public) subnet')
param hostSubnetName string

@description('Name of the container (private) subnet')
param containerSubnetName string

@description('Managed resource group name for Databricks-managed resources')
param managedResourceGroupName string = ''

var managedRgName = empty(managedResourceGroupName)
  ? '${namePrefix}-databricks-managed-rg'
  : managedResourceGroupName

resource workspace 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: '${namePrefix}-databricks-ws'
  location: location
  sku: {
    name: 'premium'
  }
  properties: {
    managedResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', managedRgName)
    publicNetworkAccess: 'Disabled'
    requiredNsgRules: 'NoAzureDatabricksRules'
    parameters: {
      customVirtualNetworkId: {
        value: vnetId
      }
      customPublicSubnetName: {
        value: hostSubnetName
      }
      customPrivateSubnetName: {
        value: containerSubnetName
      }
      enableNoPublicIp: {
        value: true
      }
    }
  }
}

// ─── Outputs ────────────────────────────────────────────────────────────────

output workspaceId string = workspace.id
output workspaceUrl string = workspace.properties.workspaceUrl
output managedResourceGroupId string = workspace.properties.managedResourceGroupId
