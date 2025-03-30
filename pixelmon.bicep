param location string = resourceGroup().location

// Container Group Parameters
@description('The number of CPU cores to allocate to the container group.')
param cpuCores int = 2
@description('The amount of memory (in GB) to allocate to the container group.')
param memoryInGB int = 6
@description('The name of the container group.')
param containerGroupName string = 'pixelmon-server'
@description('Should the container group be deployed as a spot instance? Spot instances are cheaper but can be evicted at any time.')
param spotInstance bool = true

// Storage Parameters
param storageAccountName string = substring('pixelmondata${uniqueString(resourceGroup().id)}', 0, 24)

// Logging Parameters
@description('If true, enables debug mode by deploying a log analytics workspace and setting up diagnostics.')
param enableLogAnalytics bool = false
param logAnalyticsWorkspaceName string = 'gaming-container-logs-${uniqueString(resourceGroup().id)}'
param logRetentionInDays int = 30

// Pixelmon Specific Parameters
@description('The name of the file share for the Pixelmon container data.')
param fileShareName string = 'minecraft-data'
@description('The version of the Minecraft server image to use. For example, "java8" or "java11". See https://docker-minecraft-server.readthedocs.io/en/latest/versions/java/ for more details.')
param imageVersion string = 'java8-multiarch'
@description('The version of the Pixelmon modpack to use.')
param pixelmonModpackVersion string = ''
@description('The name of the Minecraft server.')
param serverName string = 'My Pixelmon Server'
@description('An array of white-listed UUIDs for non-op players.')
param whitelist array = []
@description('An array of operator UUIDs for players.')
param ops array = []
@description('Additional mods to include beyond the default Pixelmon modpack.')
param additionalMods array = []
@description('API key for CurseForge to download the modpack')
@secure()
param curseForgeApiKey string

@description('The full white-list of UUIDs for players. This includes both the white-listed and operator UUIDs.')
var fullWhitelist = union(whitelist, ops)

// Storage Account for persistent storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

// Storage Account File Service for the file share
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

// File Share for the data volume
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2024-01-01' = {
  parent: fileService
  name: fileShareName
  properties: {
    shareQuota: 100
  }
}

// Log Analytics Workspace for container logs
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = if (enableLogAnalytics) {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionInDays
  }
}

// Get storage account key for mounting the file share
var storageAccountKey = storageAccount.listKeys().keys[0].value

// Container Group
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  properties: {
    containers: [
      {
        name: 'pixelmon'
        properties: {
          image: 'itzg/minecraft-server:${imageVersion}'
          ports: [
            { port: 25565, protocol: 'TCP' }
          ]
          environmentVariables: [
            { name: 'EULA', value: 'TRUE' }
            { name: 'MAX_MEMORY', value: '${memoryInGB - 1}G' }
            { name: 'TYPE', value: 'AUTO_CURSEFORGE' }
            { name: 'SERVER_NAME', value: serverName }
            { name: 'WHITELIST', value: join(fullWhitelist, ',') }
            { name: 'OPS', value: join(ops, ',') }
            { name: 'ALLOW_FLIGHT', value: 'true' }
            { name: 'CF_FORCE_SYNCHRONIZE', value: 'true' }
            { name: 'CF_FORCE_INCLUDE_MODS', value: 'pixelmon,fancymenu' }
            { name: 'CURSEFORGE_FILES', value: join(additionalMods, ',') }
            { name: 'CF_SLUG', value: 'the-pixelmon-modpack' }
            { name: 'CF_FILENAME_MATCHER', value: pixelmonModpackVersion }
            { name: 'CF_API_KEY', secureValue: curseForgeApiKey }
          ]
          resources: {
            requests: { cpu: cpuCores, memoryInGB: memoryInGB }
          }
          volumeMounts: [
            { name: 'pixelmon-datavolume', mountPath: '/data' }
          ]
        }
      }
    ]
    osType: 'Linux'
    priority: spotInstance ? 'Spot' : 'Regular'
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Public'
      ports: [
        { port: 25565, protocol: 'TCP' } // Pixelmon port
      ]
      dnsNameLabel: toLower(containerGroupName)
    }
    volumes: [
      {
        name: 'pixelmon-datavolume'
        azureFile: {
          shareName: fileShareName
          storageAccountName: storageAccount.name
          storageAccountKey: storageAccountKey
        }
      }
    ]
    diagnostics: enableLogAnalytics
      ? {
          logAnalytics: {
            workspaceId: logAnalyticsWorkspace.properties.customerId
            workspaceKey: logAnalyticsWorkspace.listKeys().primarySharedKey
            logType: 'ContainerInsights'
          }
        }
      : null
  }
  dependsOn: [
    fileShare
  ]
}

// Diagnostic settings for container group
resource containerDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableLogAnalytics) {
  name: '${containerGroupName}-diagnostics'
  scope: containerGroup
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// --- Outputs ---

output containerGroupFQDN string = containerGroup.properties.ipAddress.fqdn
output containerGroupIP string = containerGroup.properties.ipAddress.ip
output logAnalyticsWorkspaceId string = enableLogAnalytics ? logAnalyticsWorkspace.id : 'Log Analytics not enabled'
