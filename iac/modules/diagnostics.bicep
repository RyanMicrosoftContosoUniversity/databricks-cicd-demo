// Diagnostics module — Log Analytics workspace + diagnostic settings for Databricks audit logging

@description('Azure region')
param location string

@description('Prefix for resource names')
param namePrefix string

@description('Name of the Databricks workspace to monitor')
param databricksWorkspaceName string

// ─── Log Analytics Workspace ─────────────────────────────────────────────────

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-log-analytics'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
  }
}

// ─── Reference existing Databricks workspace ─────────────────────────────────

resource databricksWorkspace 'Microsoft.Databricks/workspaces@2024-05-01' existing = {
  name: databricksWorkspaceName
}

// ─── Diagnostic Settings on Databricks ───────────────────────────────────────

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${namePrefix}-dbw-diagnostics'
  scope: databricksWorkspace
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'dbfs'
        enabled: true
      }
      {
        category: 'clusters'
        enabled: true
      }
      {
        category: 'accounts'
        enabled: true
      }
      {
        category: 'jobs'
        enabled: true
      }
      {
        category: 'notebook'
        enabled: true
      }
      {
        category: 'ssh'
        enabled: true
      }
      {
        category: 'workspace'
        enabled: true
      }
      {
        category: 'secrets'
        enabled: true
      }
      {
        category: 'sqlPermissions'
        enabled: true
      }
      {
        category: 'unityCatalog'
        enabled: true
      }
    ]
  }
}

// ─── Outputs ────────────────────────────────────────────────────────────────

output logAnalyticsWorkspaceId string = logAnalytics.id
