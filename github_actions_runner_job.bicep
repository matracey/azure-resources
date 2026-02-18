param location string = resourceGroup().location

// Container Apps Environment Parameters
@description('The name of the Container Apps environment.')
param environmentName string = 'env-github-runners'

// Container Image Parameters
@description('The container registry server (e.g., ghcr.io, myregistry.azurecr.io).')
param containerRegistryServer string = 'ghcr.io'
@description('The full container image name and tag for the GitHub Actions runner (e.g., myorg/github-actions-runner:1.0).')
param containerImageName string
@description('The username for the container registry. Leave empty for registries that use token-based auth.')
param containerRegistryUsername string = ''
@description('The password or token for the container registry. Leave empty for public images.')
@secure()
param containerRegistryPassword string = ''

// Runner Job Parameters
@description('The name of the Container Apps job for the GitHub Actions runner.')
param jobName string = 'github-actions-runner-job'
@description('The number of CPU cores to allocate to the runner.')
param cpuCores string = '0.5'
@description('The amount of memory to allocate to the runner.')
param memory string = '1Gi'

// GitHub Configuration
@description('The GitHub personal access token used for runner registration and scale rule authentication.')
@secure()
param githubPat string
@description('The GitHub repository owner (username or organization).')
param repoOwner string
@description('The GitHub repository name.')
param repoName string
@description('The registration token API URL for the GitHub Actions runner. For example: https://api.github.com/repos/{owner}/{repo}/actions/runners/registration-token')
param registrationTokenApiUrl string = 'https://api.github.com/repos/${repoOwner}/${repoName}/actions/runners/registration-token'

// Scale Rule Parameters
@description('The GitHub API URL. Update this if you are using GitHub Enterprise.')
param githubApiUrl string = 'https://api.github.com'
@description('The minimum number of job executions per polling interval.')
param minExecutions int = 0
@description('The maximum number of job executions per polling interval.')
param maxExecutions int = 10
@description('The polling interval in seconds at which to evaluate the scale rule.')
param pollingInterval int = 30
@description('The maximum duration in seconds a replica can execute.')
param replicaTimeout int = 600

// Logging Parameters
@description('If true, enables Log Analytics for the Container Apps environment.')
param enableLogAnalytics bool = false
@description('The name of the Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'github-runner-logs-${uniqueString(resourceGroup().id)}'
@description('The number of days to retain logs.')
param logRetentionInDays int = 30

// --- Log Analytics Workspace (optional) ---

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

// --- Container Apps Environment ---

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: enableLogAnalytics
    ? {
        appLogsConfiguration: {
          destination: 'log-analytics'
          logAnalyticsConfiguration: {
            customerId: logAnalyticsWorkspace!.properties.customerId
            sharedKey: logAnalyticsWorkspace!.listKeys().primarySharedKey
          }
        }
      }
    : {}
}

// --- Container Apps Job (Event-Driven GitHub Actions Runner) ---

var registryConfig = !empty(containerRegistryUsername) ? [
  {
    server: containerRegistryServer
    username: containerRegistryUsername
    passwordSecretRef: 'registry-password'
  }
] : [
  {
    server: containerRegistryServer
  }
]

var registrySecret = !empty(containerRegistryPassword) ? [
  {
    name: 'registry-password'
    value: containerRegistryPassword
  }
] : []

resource githubRunnerJob 'Microsoft.App/jobs@2024-03-01' = {
  name: jobName
  location: location
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      triggerType: 'Event'
      replicaTimeout: replicaTimeout
      replicaRetryLimit: 0
      eventTriggerConfig: {
        replicaCompletionCount: 1
        parallelism: 1
        scale: {
          minExecutions: minExecutions
          maxExecutions: maxExecutions
          pollingInterval: pollingInterval
          rules: [
            {
              name: 'github-runner'
              type: 'github-runner'
              metadata: {
                githubAPIURL: githubApiUrl
                owner: repoOwner
                runnerScope: 'repo'
                repos: repoName
                targetWorkflowQueueLength: '1'
              }
              auth: [
                {
                  secretRef: 'personal-access-token'
                  triggerParameter: 'personalAccessToken'
                }
              ]
            }
          ]
        }
      }
      secrets: union([
        {
          name: 'personal-access-token'
          value: githubPat
        }
      ], registrySecret)
      registries: registryConfig
    }
    template: {
      containers: [
        {
          name: 'github-actions-runner'
          image: '${containerRegistryServer}/${containerImageName}'
          resources: {
            cpu: json(cpuCores)
            memory: memory
          }
          env: [
            {
              name: 'GITHUB_PAT'
              secretRef: 'personal-access-token'
            }
            {
              name: 'GH_URL'
              value: 'https://github.com/${repoOwner}/${repoName}'
            }
            {
              name: 'REGISTRATION_TOKEN_API_URL'
              value: registrationTokenApiUrl
            }
          ]
        }
      ]
    }
  }
}

// --- Outputs ---

output environmentId string = containerAppsEnvironment.id
output jobName string = githubRunnerJob.name
output logAnalyticsWorkspaceId string = enableLogAnalytics ? logAnalyticsWorkspace.id : 'Log Analytics not enabled'
