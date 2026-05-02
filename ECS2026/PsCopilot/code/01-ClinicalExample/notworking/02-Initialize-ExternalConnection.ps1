# . (Join-Path $PSScriptRoot "Initialize-GraphClient.ps1")
# . (Join-Path $PSScriptRoot "ConnectionConfiguration.ps1")
if (-not (Get-Command New-CCProperty -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "New-CCProperty.ps1")
}

$credential = Get-Secret -Name $global:mainApp.SecretName
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Connect-MgGraph -ClientSecretCredential $credential -TenantId $global:mainApp.TenantId -NoWelcome -ContextScope Process

[hashtable]$adaptiveCard = @{}
$adaptiveCard += Get-Content -Path (Join-Path $PSScriptRoot "resultLayout.json") -Raw | ConvertFrom-Json -AsHashtable

$externalConnection = @{
    userId     = "e1251b10-1ba4-49e3-b35a-933e3f21772b"
    connection = @{
        id               = $global:mainApp.Id
        name             = $global:mainApp.Name
        description      = $global:mainApp.Description
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
        searchSettings   = @{
            searchResultTemplates = @(
                @{
                    id       = $global:mainApp.Id
                    priority = 1
                    layout   = @{
                        additionalProperties = $adaptiveCard
                    }
                }
            )
        }
    }
    
    # https://learn.microsoft.com/graph/connecting-external-content-manage-schema
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
