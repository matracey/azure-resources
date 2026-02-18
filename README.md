# Azure Resources

A collection of Azure Bicep templates for deploying cloud infrastructure.

## Templates

### Gaming Container Group (`gaming_container_group.bicep`)

Deploys an Azure Container Instance group running a **Pixelmon** (Minecraft) server, a **Terraria** (TShock) server, and a **Traefik** reverse proxy, all backed by persistent Azure File Shares.

#### Resources Created

| Resource | Description |
|---|---|
| **Storage Account** | `Standard_LRS` StorageV2 account with file shares for Pixelmon, Terraria, and Traefik data |
| **Container Group** | Linux container group with three containers (Pixelmon, Terraria, Traefik). Supports spot instances. |
| **Log Analytics Workspace** | *(Optional)* Deployed when `enableLogAnalytics` is `true` for container diagnostics |
| **Diagnostic Settings** | *(Optional)* Sends container logs and metrics to Log Analytics |

#### Containers

- **Pixelmon** — `itzg/minecraft-server` image configured for the CurseForge Pixelmon modpack. Exposes port `25565` via Traefik.
- **Terraria** — `ryshe/terraria` image running TShock. Exposes port `7777` via Traefik.
- **Traefik** — Reverse proxy handling TCP routing for both game servers. Reads dynamic configuration from an Azure File Share. Exposes ports `80`, `443`, `25565`, and `7777`.

#### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `location` | `string` | Resource group location | Deployment region |
| `cpuCores` | `int` | `2` | CPU cores allocated to each game container |
| `memoryInGB` | `int` | `6` | Memory (GB) allocated to each game container |
| `containerGroupName` | `string` | `gaming-container` | Name of the container group |
| `spotInstance` | `bool` | `true` | Deploy as a spot instance (cheaper, but can be evicted) |
| `dockerHubUsername` | `string` | — | Docker Hub username for pulling images |
| `dockerHubPersonalAccessToken` | `string` (secure) | — | Docker Hub PAT for pulling images |
| `storageAccountName` | `string` | Auto-generated | Name of the storage account |
| `enableLogAnalytics` | `bool` | `false` | Enable Log Analytics workspace and diagnostics |
| `logAnalyticsWorkspaceName` | `string` | Auto-generated | Log Analytics workspace name |
| `logRetentionInDays` | `int` | `30` | Log retention period in days |
| `pixelmonFileShareName` | `string` | `minecraft-data` | File share name for Pixelmon data |
| `pixelmonImageVersion` | `string` | `java8-multiarch` | Minecraft server image tag |
| `pixelmonModpackVersion` | `string` | `''` | Pixelmon modpack version filter |
| `pixelmonServerName` | `string` | `My Pixelmon Server` | Minecraft server name |
| `pixelmonWhitelist` | `array` | `[]` | White-listed player UUIDs |
| `pixelmonOps` | `array` | `[]` | Operator player UUIDs |
| `pixelmonAdditionalMods` | `array` | `[]` | Additional CurseForge mods to include |
| `curseForgeApiKey` | `string` (secure) | — | CurseForge API key for modpack downloads |
| `terrariaFileShareName` | `string` | `terraria-data` | File share name for Terraria data |
| `terrariaImageVersion` | `string` | `latest` | Terraria server image tag |
| `terrariaTShockVersion` | `string` | `v5.2.2` | TShock version |
| `terrariaLogDirPath` | `string` | `/tshock/logs` | Terraria log directory path |
| `terrariaConfigDirPath` | `string` | `/root/.local/share/Terraria/Worlds` | Terraria config directory path |
| `terrariaWorldFileName` | `string` | `world.wld` | World file name |

#### Outputs

| Output | Description |
|---|---|
| `containerGroupFQDN` | Fully qualified domain name of the container group |
| `containerGroupIP` | Public IP address of the container group |
| `logAnalyticsWorkspaceId` | Log Analytics workspace resource ID (or message if disabled) |

### GitHub Actions Runner Job (`github_actions_runner_job.bicep`)

Deploys an event-driven, self-hosted **GitHub Actions runner** on Azure Container Apps. The runner automatically scales based on queued workflow jobs using a KEDA `github-runner` scale rule, pulling a custom runner image from a private Azure Container Registry.

#### Resources Created

| Resource | Description |
|---|---|
| **Container Apps Environment** | Managed environment for running the Container Apps job |
| **Azure Container Registry** | `Basic` SKU registry for storing the custom runner image |
| **User-Assigned Managed Identity** | Identity with `AcrPull` role for pulling images from ACR |
| **AcrPull Role Assignment** | Grants the managed identity pull access to the container registry |
| **Container Apps Job** | Event-triggered job that spins up runner replicas in response to queued GitHub Actions workflows |
| **Log Analytics Workspace** | *(Optional)* Deployed when `enableLogAnalytics` is `true` |

#### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `location` | `string` | Resource group location | Deployment region |
| `environmentName` | `string` | `env-github-runners` | Container Apps environment name |
| `containerRegistryName` | `string` | Auto-generated | Azure Container Registry name (globally unique) |
| `identityName` | `string` | `github-runner-identity` | Managed identity name for ACR pull |
| `jobName` | `string` | `github-actions-runner-job` | Container Apps job name |
| `containerImageName` | `string` | `github-actions-runner:1.0` | Runner container image name and tag |
| `cpuCores` | `string` | `2.0` | CPU cores allocated to the runner |
| `memory` | `string` | `4Gi` | Memory allocated to the runner |
| `githubPat` | `string` (secure) | — | GitHub PAT for runner registration and scale rule auth |
| `repoOwner` | `string` | — | GitHub repository owner (user or org) |
| `repoName` | `string` | — | GitHub repository name |
| `registrationTokenApiUrl` | `string` | Auto-generated | Runner registration token API URL |
| `githubApiUrl` | `string` | `https://api.github.com` | GitHub API URL (update for GitHub Enterprise) |
| `minExecutions` | `int` | `0` | Minimum job executions per polling interval |
| `maxExecutions` | `int` | `10` | Maximum job executions per polling interval |
| `pollingInterval` | `int` | `30` | Scale rule polling interval in seconds |
| `replicaTimeout` | `int` | `1800` | Maximum replica execution duration in seconds |
| `enableLogAnalytics` | `bool` | `false` | Enable Log Analytics for the environment |
| `logAnalyticsWorkspaceName` | `string` | Auto-generated | Log Analytics workspace name |
| `logRetentionInDays` | `int` | `30` | Log retention period in days |

#### Outputs

| Output | Description |
|---|---|
| `environmentId` | Container Apps environment resource ID |
| `containerRegistryLoginServer` | ACR login server hostname |
| `managedIdentityId` | Managed identity resource ID |
| `jobName` | Container Apps job name |
| `logAnalyticsWorkspaceId` | Log Analytics workspace resource ID (or message if disabled) |
