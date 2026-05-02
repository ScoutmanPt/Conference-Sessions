$ErrorActionPreference = "Stop"
# msg prefix
$prefix = "[CoPilot Connector][02-CreateConnection]:"

Write-Host "$($prefix) Initialize External Connection [$($global:mainApp.DisplayName)]" -ForegroundColor Cyan

##read the main app configuration saved by 01-Initialize-EntraApp.ps1
$configPath = Join-Path $PSScriptRoot "config.json"
if (Test-Path -Path $configPath) {
    Write-Host "$($prefix)  Reading main app configuration from $configPath..." -ForegroundColor Cyan
    $mainAppConfig = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    $global:mainApp = @{
        Id = $mainAppConfig.Id
        DisplayName = $mainAppConfig.DisplayName
        Description = $mainAppConfig.Description
        TenantId = $mainAppConfig.TenantId
        ClientId = $mainAppConfig.ClientId
        SecretName = $mainAppConfig.SecretName
    }
}


# Read connector settings saved by 01-Initialize-EntraApp.ps1.
Write-Host "$($prefix)  Reading connector settings from `$global:mainApp..." -ForegroundColor Cyan
$connectionId = $global:mainApp.Id
$connectionName = $global:mainApp.DisplayName
$connectionDescription = $global:mainApp.Description
$tenantId = $global:mainApp.TenantId
$secretName = $global:mainApp.SecretName

# Microsoft Graph requires the search result template id to be 16 characters or less.
Write-Host "$($prefix)  Preparing search result template id..." -ForegroundColor Cyan


# Read the app-only credential created by 01-Initialize-EntraApp.ps1.
Write-Host "$($prefix)  Reading app-only credential from SecretManagement secret '$secretName'..." -ForegroundColor Cyan
$credential = Get-Secret -Name $secretName

# Connect to Microsoft Graph with the connector app registration.
Write-Host "$($prefix)  Connecting to Microsoft Graph with app-only credentials..." -ForegroundColor Cyan
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Connect-MgGraph -ClientSecretCredential $credential -TenantId $tenantId -NoWelcome -ContextScope Process

# Load the adaptive card layout used for search result rendering.
Write-Host "$($prefix)  Loading adaptive card layout from resultLayout.json..." -ForegroundColor Cyan

# Initialize to an empty variables to make sure the same are loaded in configuration script and connection initialization script
$externalConnection=$null
. $PSScriptRoot\Get-ConnConfiguration.ps1


# Convert the connection payload to JSON and create the external connection.
Write-Host "$($prefix)  Creating external connection '$connectionId'..." -foregroundColor Cyan

New-MgExternalConnection -BodyParameter $externalConnection.connection -ErrorAction Stop | Out-Null


# Build the schema update body and attach it to the external connection.
Write-Host "$($prefix)  Creating schema..." -foregroundColor Cyan
$body = @{
    baseType = "microsoft.graph.externalItem"
    properties = $externalConnection.schema
}
Update-MgExternalConnectionSchema -ExternalConnectionId $externalConnection.connection.id -BodyParameter $body -ErrorAction Stop
Write-Host "$($prefix)  Waiting for the schema to get provisioned..." -ForegroundColor Yellow -NoNewline
do {
    $connection = Get-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id
    Start-Sleep -Seconds 30
    Write-Host "." -NoNewLine -ForegroundColor Yellow
} while ($connection.State -eq 'draft')




## Copilot Visibility is managed from the Microsoft 365 admin center:
## Copilot > Connectors > Your Connections > select the connection > Copilot Visibility.
## The Microsoft Graph connection API does not currently document a supported create/update path for that toggle.

Write-Host "`nCopilot Visibility is managed from the Microsoft 365 admin center:" -ForegroundColor Green
Write-Host "Copilot > Connectors > Your Connections > select the connection > Copilot Visibility" -ForegroundColor Green
Write-Host "The Microsoft Graph connection API does not currently document a supported create/update path for that toggle." -ForegroundColor Green
Write-Host "`n$($prefix)Connection created" -ForegroundColor Cyan





# Write-Host "Creating or updating external connection..." -NoNewLine
# while ($existingConnection.State -eq 'draft') {
#     $existingConnection = Get-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id
#     Start-Sleep -Seconds 10
#     Write-Host " still in draft" -NoNewLine -ForegroundColor Yellow
# } 
# while ( $null -ne $existingConnection){
#     Remove-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id  -OnErrorAction SilentlyContinue       
#     Start-Sleep -Seconds 5
#     $existingConnection = Get-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id -ErrorAction SilentlyContinue
# } 

# if ($existingConnection) {
#     #Update-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id -BodyParameter $externalConnection.connection -ErrorAction Stop | Out-Null
    
# }
# else {
#     New-MgExternalConnection -BodyParameter $externalConnection.connection -ErrorAction Stop | Out-Null
# }

# Write-Host "DONE" -ForegroundColor Green

# Write-Host "Creating schema..." -NoNewLine
# $body = @{
#     baseType = "microsoft.graph.externalItem"
#     properties = $externalConnection.schema
# }

# Update-MgExternalConnectionSchema -ExternalConnectionId $externalConnection.connection.id -BodyParameter $body -ErrorAction Stop
# Write-Host "DONE" -ForegroundColor Green

# Write-Host "Waiting for the schema to get provisioned..." -ForegroundColor Yellow -NoNewline
# do {
#     $connection = Get-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id
#     Start-Sleep -Seconds 60
#     Write-Host "." -NoNewLine -ForegroundColor Yellow
# } while ($connection.State -eq 'draft')

# Write-Host "DONE" -ForegroundColor Green

# Write-Host "Set enabledContentExperiences..." -ForegroundColor Yellow -NoNewline
# $body = @{
#   enabledContentExperiences = @("search")
# } | ConvertTo-Json

# Invoke-MgGraphRequest `
#   -Method PATCH `
#   -Uri "https://graph.microsoft.com/beta/external/connections/$connectionId" `
#   -Body $body `
#   -ContentType "application/json"
# Write-Host "DONE" -ForegroundColor Green
# . (Join-Path $PSScriptRoot "03-Import-Content.ps1")
