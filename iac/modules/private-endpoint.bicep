// Private endpoint module — Front-end + browser auth private endpoints for Databricks,
// plus Private DNS zone (privatelink.azuredatabricks.net) linked to the VNet.

@description('Azure region')
param location string

@description('Prefix for resource names')
param namePrefix string

@description('Resource ID of the Databricks workspace')
param workspaceId string

@description('Resource ID of the private endpoint subnet')
param peSubnetId string

@description('Resource ID of the VNet (for DNS zone link)')
param vnetId string

// ─── Private DNS Zone ────────────────────────────────────────────────────────

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.azuredatabricks.net'
  location: 'global'
}

resource dnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: '${namePrefix}-dns-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// ─── Front-end Private Endpoint (UI / API) ───────────────────────────────────

resource uiApiEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${namePrefix}-dbw-ui-pe'
  location: location
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${namePrefix}-dbw-ui-plsc'
        properties: {
          privateLinkServiceId: workspaceId
          groupIds: [
            'databricks_ui_api'
          ]
        }
      }
    ]
  }
}

resource uiApiDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: uiApiEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'databricks-ui-api'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// ─── Browser Authentication Private Endpoint ─────────────────────────────────
// Required for SSO login over private networks.

resource browserAuthEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${namePrefix}-dbw-auth-pe'
  location: location
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${namePrefix}-dbw-auth-plsc'
        properties: {
          privateLinkServiceId: workspaceId
          groupIds: [
            'browser_authentication'
          ]
        }
      }
    ]
  }
}

resource browserAuthDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: browserAuthEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'databricks-browser-auth'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// ─── Outputs ────────────────────────────────────────────────────────────────

output uiApiEndpointId string = uiApiEndpoint.id
output browserAuthEndpointId string = browserAuthEndpoint.id
output privateDnsZoneId string = privateDnsZone.id
