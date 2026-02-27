// VNet module — Virtual Network with Databricks subnets, Private Endpoint subnet,
// VNet Data Gateway subnet, NAT Gateway, and Public IP

@description('Azure region')
param location string

@description('Prefix for resource names')
param namePrefix string

@description('VNet address space')
param vnetCidr string = '10.0.0.0/16'

@description('Host (public) subnet CIDR')
param hostSubnetCidr string = '10.0.1.0/24'

@description('Container (private) subnet CIDR')
param containerSubnetCidr string = '10.0.2.0/24'

@description('Private endpoint subnet CIDR')
param privateEndpointSubnetCidr string = '10.0.3.0/24'

@description('VNet Data Gateway delegated subnet CIDR')
param gatewaySubnetCidr string = '10.0.4.0/24'

@description('Management/jumpbox subnet CIDR')
param mgmtSubnetCidr string = '10.0.5.0/24'

@description('Resource ID of the host subnet NSG')
param hostNsgId string

@description('Resource ID of the container subnet NSG')
param containerNsgId string

@description('Resource ID of the gateway subnet NSG')
param gatewayNsgId string

// ─── NAT Gateway Public IP ──────────────────────────────────────────────────

resource natPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${namePrefix}-nat-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// ─── NAT Gateway ────────────────────────────────────────────────────────────

resource natGateway 'Microsoft.Network/natGateways@2024-05-01' = {
  name: '${namePrefix}-nat-gw'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      { id: natPublicIp.id }
    ]
  }
}

// ─── Virtual Network ────────────────────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${namePrefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetCidr
      ]
    }
  }
}

// ─── Host Subnet (public) ───────────────────────────────────────────────────

resource hostSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: '${namePrefix}-host-subnet'
  properties: {
    addressPrefix: hostSubnetCidr
    networkSecurityGroup: {
      id: hostNsgId
    }
    natGateway: {
      id: natGateway.id
    }
    delegations: [
      {
        name: 'databricks-host-delegation'
        properties: {
          serviceName: 'Microsoft.Databricks/workspaces'
        }
      }
    ]
  }
}

// ─── Container Subnet (private) ─────────────────────────────────────────────

resource containerSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: '${namePrefix}-container-subnet'
  dependsOn: [
    hostSubnet
  ]
  properties: {
    addressPrefix: containerSubnetCidr
    networkSecurityGroup: {
      id: containerNsgId
    }
    natGateway: {
      id: natGateway.id
    }
    delegations: [
      {
        name: 'databricks-container-delegation'
        properties: {
          serviceName: 'Microsoft.Databricks/workspaces'
        }
      }
    ]
  }
}

// ─── Private Endpoint Subnet ─────────────────────────────────────────────────

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: '${namePrefix}-pe-subnet'
  dependsOn: [
    containerSubnet
  ]
  properties: {
    addressPrefix: privateEndpointSubnetCidr
  }
}

// ─── VNet Data Gateway Subnet ────────────────────────────────────────────────

resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: '${namePrefix}-gateway-subnet'
  dependsOn: [
    peSubnet
  ]
  properties: {
    addressPrefix: gatewaySubnetCidr
    networkSecurityGroup: {
      id: gatewayNsgId
    }
    serviceEndpoints: [
      {
        service: 'Microsoft.AzureActiveDirectory'
      }
    ]
    delegations: [
      {
        name: 'powerplatform-vnet-delegation'
        properties: {
          serviceName: 'Microsoft.PowerPlatform/vnetaccesslinks'
        }
      }
    ]
  }
}

// ─── Management / Jumpbox Subnet ─────────────────────────────────────────────

resource mgmtSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: '${namePrefix}-mgmt-subnet'
  dependsOn: [
    gatewaySubnet
  ]
  properties: {
    addressPrefix: mgmtSubnetCidr
  }
}

// ─── Outputs ────────────────────────────────────────────────────────────────

output vnetId string = vnet.id
output vnetName string = vnet.name
output hostSubnetName string = hostSubnet.name
output containerSubnetName string = containerSubnet.name
output peSubnetId string = peSubnet.id
output gatewaySubnetName string = gatewaySubnet.name
output mgmtSubnetId string = mgmtSubnet.id
output natGatewayPublicIp string = natPublicIp.properties.ipAddress
