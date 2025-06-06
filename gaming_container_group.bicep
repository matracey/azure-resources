param location string = resourceGroup().location

// Container Group Parameters
@description('The number of CPU cores to allocate to the container group.')
param cpuCores int = 2
@description('The amount of memory (in GB) to allocate to the container group.')
param memoryInGB int = 6
@description('The name of the container group.')
param containerGroupName string = 'gaming-container'
@description('Should the container group be deployed as a spot instance? Spot instances are cheaper but can be evicted at any time.')
param spotInstance bool = true
@description('The Docker Hub username for pulling images.')
param dockerHubUsername string
@description('The Docker Hub personal access token for pulling images.')
@secure()
param dockerHubPersonalAccessToken string

// Storage Parameters
param storageAccountName string = substring('gamingcontainerdata${uniqueString(resourceGroup().id)}', 0, 24)

// Logging Parameters
@description('If true, enables debug mode by deploying a log analytics workspace and setting up diagnostics.')
param enableLogAnalytics bool = false
param logAnalyticsWorkspaceName string = 'gaming-container-logs-${uniqueString(resourceGroup().id)}'
param logRetentionInDays int = 30

// Pixelmon Specific Parameters
@description('The name of the file share for the Pixelmon container data.')
param pixelmonFileShareName string = 'minecraft-data'
@description('The version of the Minecraft server image to use. For example, "java8" or "java11". See https://docker-minecraft-server.readthedocs.io/en/latest/versions/java/ for more details.')
param pixelmonImageVersion string = 'java8-multiarch'
@description('The version of the Pixelmon modpack to use.')
param pixelmonModpackVersion string = ''
@description('The name of the Minecraft server.')
param pixelmonServerName string = 'My Pixelmon Server'
@description('An array of white-listed UUIDs for non-op players.')
param pixelmonWhitelist array = []
@description('An array of operator UUIDs for players.')
param pixelmonOps array = []
@description('Additional mods to include beyond the default Pixelmon modpack.')
param pixelmonAdditionalMods array = []
@description('API key for CurseForge to download the modpack')
@secure()
param curseForgeApiKey string

// Terraria Specific Parameters
@description('The name of the file share for the Terraria container data.')
param terrariaFileShareName string = 'terraria-data'
@description('The version of the Terraria server image to use.')
param terrariaImageVersion string = 'latest'
@description('The version of TShock to use.')
param terrariaTShockVersion string = 'v5.2.2'
@description('The path to the Terraria log directory.')
param terrariaLogDirPath string = '/tshock/logs'
@description('The path to the Terraria configuration directory.')
param terrariaConfigDirPath string = '/root/.local/share/Terraria/Worlds'
@description('The name of the world file.')
param terrariaWorldFileName string = 'world.wld'

@description('An array of file share names to create within the storage account.')
var fileShareNames = [
  pixelmonFileShareName
  terrariaFileShareName
]
@description('The full white-list of UUIDs for players. This includes both the white-listed and operator UUIDs.')
var fullPixelmonWhitelist = union(pixelmonWhitelist, pixelmonOps)

// --- Shared Resources ---

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
resource fileShares 'Microsoft.Storage/storageAccounts/fileServices/shares@2024-01-01' = [
  for shareName in fileShareNames: {
    parent: fileService
    name: shareName
    properties: {
      shareQuota: 100 // Quota in MB
    }
  }
]

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

// --- Module Deployment ---
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  properties: {
    containers: [
      {
        name: 'pixelmon'
        properties: {
          image: 'itzg/minecraft-server:${pixelmonImageVersion}'
          ports: [
            { port: 25565, protocol: 'TCP' }
          ]
          environmentVariables: [
            { name: 'EULA', value: 'TRUE' }
            { name: 'MAX_MEMORY', value: '${memoryInGB - 1}G' }
            { name: 'TYPE', value: 'AUTO_CURSEFORGE' }
            { name: 'SERVER_NAME', value: pixelmonServerName }
            { name: 'WHITELIST', value: join(fullPixelmonWhitelist, ',') }
            { name: 'OPS', value: join(pixelmonOps, ',') }
            { name: 'ALLOW_FLIGHT', value: 'true' }
            { name: 'CF_FORCE_SYNCHRONIZE', value: 'true' }
            { name: 'CF_FORCE_INCLUDE_MODS', value: 'pixelmon,fancymenu' }
            { name: 'CURSEFORGE_FILES', value: join(pixelmonAdditionalMods, ',') }
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
      {
        name: 'terraria'
        properties: {
          image: 'ryshe/terraria:${terrariaImageVersion}'
          ports: [
            { port: 7777, protocol: 'TCP' }
          ]
          environmentVariables: [
            { name: 'TSHOCKVERSION', value: terrariaTShockVersion }
            { name: 'LOGPATH', value: terrariaLogDirPath }
            { name: 'CONFIGPATH', value: terrariaConfigDirPath }
            { name: 'WORLD_FILENAME', value: terrariaWorldFileName }
          ]
          command: [
            '/bin/sh'
            'bootstrap.sh'
            '-autocreate'
          ]
          resources: {
            // Assuming Terraria needs similar resources, adjust if needed
            requests: { cpu: cpuCores, memoryInGB: memoryInGB }
          }
          volumeMounts: [
            { name: 'terraria-datavolume', mountPath: '/root/.local/share/Terraria' } // Mount path for Terraria world data
          ]
        }
      }
    ]
    osType: 'Linux'
    priority: spotInstance ? 'Spot' : 'Regular'
    imageRegistryCredentials: [
      {
        server: 'index.docker.io'
        username: dockerHubUsername
        password: dockerHubPersonalAccessToken
      }
    ]
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Public'
      ports: [
        { port: 25565, protocol: 'TCP' } // Pixelmon port
        { port: 7777, protocol: 'TCP' } // Terraria port
      ]
      dnsNameLabel: toLower(containerGroupName)
    }
    volumes: [
      {
        name: 'pixelmon-datavolume'
        azureFile: {
          readOnly: false
          shareName: pixelmonFileShareName
          storageAccountName: storageAccount.name
          storageAccountKey: storageAccountKey
        }
      }
      {
        name: 'terraria-datavolume'
        azureFile: {
          readOnly: false
          shareName: terrariaFileShareName
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
    fileShares
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
