param location string = resourceGroup().location

// Container Group Parameters
@description('The number of CPU cores to allocate to the container group.')
param cpuCores int = 2
@description('The amount of memory (in GB) to allocate to the container group.')
param memoryInGB int = 6
@description('The name of the container group.')
param containerGroupName string = 'pixelmon-server'

// Storage Parameters
param storageAccountName string = substring('pixelmondata${uniqueString(resourceGroup().id)}', 0, 24)

// Pixelmon Specific Parameters
@description('The name of the file share for the Pixelmon container data.')
param fileShareName string = 'minecraft-data'
@description('API key for CurseForge to download the modpack')
@secure()
param curseForgeApiKey string

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
          image: 'itzg/minecraft-server'
          ports: [
            { port: 25565, protocol: 'TCP' }
          ]
          environmentVariables: [
            { name: 'EULA', value: 'TRUE' }
            { name: 'MAX_MEMORY', value: '${memoryInGB - 1}G' }
            { name: 'TYPE', value: 'AUTO_CURSEFORGE' }
            { name: 'ALLOW_FLIGHT', value: 'true' }
            { name: 'CF_FORCE_SYNCHRONIZE', value: 'true' }
            { name: 'CF_FORCE_INCLUDE_MODS', value: 'pixelmon,fancymenu' }
            { name: 'CF_SLUG', value: 'the-pixelmon-modpack' }
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
  }
  dependsOn: [
    fileShare
  ]
}

output containerGroupFQDN string = containerGroup.properties.ipAddress.fqdn
output containerGroupIP string = containerGroup.properties.ipAddress.ip
