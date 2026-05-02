$ErrorActionPreference = "Stop"
# msg prefix
$prefix = "[CoPilot Connector]:"

Write-Host "$($prefix) Initialize External Connection [$($global:mainApp.DisplayName)]" -ForegroundColor Cyan

# Load the schema property helper when this script is run directly.
Write-Host "$($prefix)  Loading schema property helper..." -ForegroundColor Cyan
if (-not (Get-Command New-CCProperty -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "New-CCProperty.ps1")
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
$searchTemplateId = $connectionId.Substring(0, [Math]::Min($connectionId.Length, 16))

# Read the app-only credential created by 01-Initialize-EntraApp.ps1.
Write-Host "$($prefix)  Reading app-only credential from SecretManagement secret '$secretName'..." -ForegroundColor Cyan
$credential = Get-Secret -Name $secretName

# Connect to Microsoft Graph with the connector app registration.
Write-Host "$($prefix)  Connecting to Microsoft Graph with app-only credentials..." -ForegroundColor Cyan
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Connect-MgGraph -ClientSecretCredential $credential -TenantId $tenantId -NoWelcome -ContextScope Process

# Load the adaptive card layout used for search result rendering.
Write-Host "$($prefix)  Loading adaptive card layout from resultLayout.json..." -ForegroundColor Cyan
[hashtable]$adaptiveCard = @{}
$adaptiveCard += Get-Content -Path (Join-Path $PSScriptRoot "resultLayout.json") -Raw | ConvertFrom-Json -AsHashtable

# Build the external connection payload and schema definition.
Write-Host "$($prefix)  Building external connection payload..." -ForegroundColor Cyan
$externalConnection = @{
    userId     = "e1251b10-1ba4-49e3-b35a-933e3f21772b"
    connection = @{
        id               = $connectionId
        name             = $connectionName
        description      = $connectionDescription
        # Configure how source URLs map back to external item IDs.
        activitySettings = @{
            urlToItemResolvers = @(
                @{
                    "@odata.type" = "#microsoft.graph.externalConnectors.itemIdResolver"
                    urlMatchInfo  = @{
                        baseUrls   = @(
                            "https://restcountries.eu/rest/v2/name/"
                        )
                        urlPattern = "/(?<slug>[^/]+)"
                    }
                    itemId        = "{slug}"
                    priority      = 1
                }
            )
        }
        # Configure the adaptive card template shown in Microsoft Search results.
        searchSettings   = @{
            searchResultTemplates = @(
                @{
                    id       = $searchTemplateId
                    priority = 1
                    layout   = @{
                        additionalProperties = $adaptiveCard
                    }
                }
            )
        }
    }
    
    # https://learn.microsoft.com/graph/connecting-external-content-manage-schema
    # Define the external item schema using New-CCProperty.
    schema     = @(
        New-CCProperty -Name "name" -Type "String" -Queryable -Searchable -Retrievable -Labels @("title")
        New-CCProperty -Name "region" -Type "String" -Queryable -Searchable -Retrievable
        New-CCProperty -Name "subregion" -Type "String" -Queryable -Searchable -Retrievable
        New-CCProperty -Name "capital" -Type "String" -Queryable -Searchable -Retrievable
        New-CCProperty -Name "population" -Type "Int64" -Retrievable
        New-CCProperty -Name "latitude" -Type "Double" -Retrievable
        New-CCProperty -Name "longitude" -Type "Double" -Retrievable
        New-CCProperty -Name "areaInSqKm" -Type "Int64" -Retrievable
        New-CCProperty -Name "timezone" -Type "String" -Retrievable
        New-CCProperty -Name "mapUrl" -Type "String" -Retrievable -Labels @("url")
        New-CCProperty -Name "flagUrl" -Type "String" -Retrievable
        New-CCProperty -Name "borders" -Type "String" -Retrievable
        New-CCProperty -Name "languages" -Type "String" -Retrievable
        New-CCProperty -Name "currencies" -Type "String" -Retrievable
        New-CCProperty -Name "lastModifiedBy" -Type "String" -Queryable -Searchable -Retrievable -Labels @("lastModifiedBy")
        New-CCProperty -Name "lastModifiedDateTime" -Type "DateTime" -Queryable -Retrievable -Refinable -Labels @("lastModifiedDateTime")
    )
    
}

# Convert the connection payload to JSON and create the external connection.
Write-Host "$($prefix)  Creating external connection '$connectionId'..." -foregroundColor Cyan
$connectionBody = $externalConnection.connection | ConvertTo-Json -Depth 20 -Compress
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/external/connections" -Body $connectionBody -ContentType "application/json" -ErrorAction Stop | Out-Null


# Build the schema update body and attach it to the external connection.
Write-Host "$($prefix)  Creating schema..." -NoNewLine -foregroundColor Cyan
$body = @{
    baseType = "microsoft.graph.externalItem"
    properties = $externalConnection.schema
}
Update-MgExternalConnectionSchema -ExternalConnectionId $externalConnection.connection.id -BodyParameter $body -ErrorAction Stop
Write-Host "$($prefix)  Waiting for the schema to get provisioned..." -ForegroundColor Yellow -NoNewline
do {
    $connection = Get-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id
    Start-Sleep -Seconds 60
    Write-Host "." -NoNewLine -ForegroundColor Yellow
} while ($connection.State -eq 'draft')




## Copilot Visibility is managed from the Microsoft 365 admin center:
## Copilot > Connectors > Your Connections > select the connection > Copilot Visibility.
## The Microsoft Graph connection API does not currently document a supported create/update path for that toggle.
Write-Host "$($prefix)Connection created" -ForegroundColor Cyan





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
