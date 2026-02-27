// NSG module — produces three NSGs following least-privilege:
//   host-nsg:      baseline Databricks rules only
//   container-nsg: baseline Databricks rules only
//   gateway-nsg:   VNet Data Gateway subnet rules

@description('Azure region for the NSGs')
param location string

@description('Prefix for resource names')
param namePrefix string

// ─── Host Subnet NSG (baseline only) ────────────────────────────────────────

resource hostNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-host-nsg'
  location: location
  properties: {
    securityRules: baselineRules
  }
}

// ─── Container Subnet NSG (baseline only) ────────────────────────────────────
// PowerBI outbound rule removed — with Private Link, Power BI traffic arrives
// via the VNet Data Gateway through the private endpoint, not direct outbound.

resource containerNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-container-nsg'
  location: location
  properties: {
    securityRules: baselineRules
  }
}

// ─── VNet Data Gateway Subnet NSG ────────────────────────────────────────────

resource gatewayNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-gateway-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowOutbound-Databricks-PE'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowOutbound-PowerPlatform-Mgmt'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureCloud'
        }
      }
      {
        name: 'AllowOutbound-ServiceBus'
        properties: {
          priority: 300
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'ServiceBus'
        }
      }
      {
        name: 'AllowOutbound-AzureActiveDirectory'
        properties: {
          priority: 400
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureActiveDirectory'
        }
      }
      {
        name: 'DenyAllOutbound-Internet'
        properties: {
          priority: 4000
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
        }
      }
    ]
  }
}

// ─── Baseline rules required for all Databricks subnets ─────────────────────

var baselineRules = [
  // Inbound
  {
    name: 'AllowInbound-VNet'
    properties: {
      priority: 100
      direction: 'Inbound'
      access: 'Allow'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: 'VirtualNetwork'
      destinationAddressPrefix: 'VirtualNetwork'
    }
  }
  // Outbound — Databricks control plane
  {
    name: 'AllowOutbound-Databricks'
    properties: {
      priority: 100
      direction: 'Outbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRanges: [
        '443'
        '3306'
        '8443-8451'
      ]
      sourceAddressPrefix: 'VirtualNetwork'
      destinationAddressPrefix: 'AzureDatabricks'
    }
  }
  // Outbound — Metastore (SQL)
  {
    name: 'AllowOutbound-Sql'
    properties: {
      priority: 110
      direction: 'Outbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '3306'
      sourceAddressPrefix: 'VirtualNetwork'
      destinationAddressPrefix: 'Sql'
    }
  }
  // Outbound — Azure Storage (artifacts, logs)
  {
    name: 'AllowOutbound-Storage'
    properties: {
      priority: 120
      direction: 'Outbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: 'VirtualNetwork'
      destinationAddressPrefix: 'Storage'
    }
  }
  // Outbound — VNet internal
  {
    name: 'AllowOutbound-VNet'
    properties: {
      priority: 130
      direction: 'Outbound'
      access: 'Allow'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: 'VirtualNetwork'
      destinationAddressPrefix: 'VirtualNetwork'
    }
  }
  // Outbound — EventHub (logging)
  {
    name: 'AllowOutbound-EventHub'
    properties: {
      priority: 140
      direction: 'Outbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '9093'
      sourceAddressPrefix: 'VirtualNetwork'
      destinationAddressPrefix: 'EventHub'
    }
  }
]

// ─── Outputs ────────────────────────────────────────────────────────────────

output hostNsgId string = hostNsg.id
output containerNsgId string = containerNsg.id
output gatewayNsgId string = gatewayNsg.id
