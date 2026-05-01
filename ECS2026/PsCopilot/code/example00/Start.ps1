$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot "../_modules/PDragon.CopilotConnector/PDragon.CopilotConnector.psd1") -Force

# Reuse the same base name for the connector, stored secret, and config file.
$connectorDisplayName = "Test Conn12"
$connectorName = $connectorDisplayName.ToLower().Replace(" ", "")

$secretName = "$($connectorName)powershell"
$config = (Join-Path $PSScriptRoot "config.ini") 
$activityUserId = [guid]::NewGuid().ToString()

# Retrieve country data from the REST Countries API and normalize it into the
# shape expected by the connector import step.
function Get-RESTCountries {
    param(
        [string] $Url
    )

    $restCountries = @()

    # The REST Countries API limits how many fields can be requested at once, so
    # the script retrieves core and detail fields separately and joins them in memory.
    $coreFields = "name,region,subregion,capital,population,latlng,area,timezones,maps,flags"
    $detailFields = "name,cca3,borders,languages,currencies"
    $json = Invoke-RestMethod -Uri "$Url/all?fields=$coreFields" -Method Get -ContentType "application/json"
    $details = Invoke-RestMethod -Uri "$Url/all?fields=$detailFields" -Method Get -ContentType "application/json"
    $detailsByName = @{}
    $countryNamesByCode = @{}

    $details | ForEach-Object {
        $detailsByName[$_.name.common] = $_
        $countryNamesByCode[$_.cca3] = $_.name.common
    }

    $index = 1

    $json | ForEach-Object {
        $country = $_
        $countryDetails = $detailsByName[$country.name.common]

        $borderCountries = @($countryDetails.borders | ForEach-Object {
                if ($countryNamesByCode.ContainsKey($_)) {
                    $countryNamesByCode[$_]
                }
            })

        Write-Host "Retrieving $($country.name.common)... $index of $($json.Count)" -ForegroundColor Yellow
        # Create custom object and add to $restCountries array
        $restCountries += [pscustomobject]@{
            Name       = $country.name.common
            Region     = $country.region
            Subregion  = $country.subregion
            Capital    = if ($country.capital) { [string]::join(", ", $country.capital) } else { '' }
            Population = $country.population
            Latitude   = $country.latlng[0]
            Longitude  = $country.latlng[1]
            AreaInSqKm = $country.area
            Timezone   = if ($country.timezones) { [string]::join(", ", $country.timezones) } else { '' }
            Map        = $country.maps.googleMaps
            Flag       = $country.flags.png
            Borders    = if ($borderCountries) { [string]::join(", ", $borderCountries) } else { '' }
            Languages  = if ($countryDetails.languages.psobject.properties.value) { [string]::join(", ", $countryDetails.languages.psobject.properties.value) } else { '' }
            Currencies = if ($countryDetails.currencies.psobject.properties.value.name) { [string]::join(", ", $countryDetails.currencies.psobject.properties.value.name) } else { '' }
        }

        $index++
    }

    return $restCountries
}

# Convert the normalized country objects into external items and ingest them
# into Microsoft Graph, including one dedicated marker item for grounding tests.
function Import-ExternalItems {
    param(
        [Parameter(Mandatory)]
        [Object[]] $Content,
        [Parameter(Mandatory)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphExternalConnectorsExternalConnection] $ExternalConnection,
        [Parameter(Mandatory)]
        [string] $UserId
    )

    $startDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"

    $index = 1
    # Save the transformed source data locally so it is easy to inspect what is
    # about to be ingested into the external connection.
    $Content | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $PSScriptRoot "restcountries-content.json") -Encoding utf8
    $Content | ForEach-Object {
        $item = @{
            id         = $index
            properties = @{
                name                 = $_.Name
                region               = $_.Region
                subregion            = $_.Subregion
                capital              = $_.Capital
                population           = $_.Population
                latitude             = $_.Latitude
                longitude            = $_.Longitude
                areaInSqKm           = $_.AreaInSqKm
                timezone             = $_.Timezone
                mapUrl               = [System.Uri]::new($_.Map).ToString()
                flagUrl              = [System.Uri]::new($_.Flag).ToString()
                borders              = $_.Borders
                languages            = $_.Languages
                currencies           = $_.Currencies
                lastModifiedBy       = "REST Countries"
                lastModifiedDateTime = $startDate
            }
            content    = @{
                value = "$($_.Name) is in $($_.Region), $($_.Subregion). Its capital is $($_.Capital). Population is $($_.Population). Languages: $($_.Languages). Currencies: $($_.Currencies). Border countries: $($_.Borders)."
                type  = 'text'
            }
            acl        = @(
                @{
                    accessType = "grant"
                    type       = "everyone"
                    value      = "everyone"
                }
            )
          
            activities = @(@{
                    "@odata.type" = "#microsoft.graph.externalConnectors.externalActivity"
                    type          = "created"
                    startDateTime = $startDate
                    performedBy   = @{
                        type = "user"
                        id   = $UserId
                    }
                })
        }

        try {
            # Each country becomes an external item with both structured properties
            # and a natural-language content field for better Copilot grounding.
            Set-MgExternalConnectionItem -ExternalConnectionId $ExternalConnection.Id -ExternalItemId $item.id -BodyParameter $item -ErrorAction Stop | Out-Null
      
            Write-Host "Imported $($item.properties.name)... $index of $($Content.Count)" -ForegroundColor Green  
        }
        catch {
            Write-Error "Failed to import $($item.properties.name)"
            Write-Error $_.Exception.Message
        }
    
        $index++
    }

    # Add a single marker record that can be used later to prove Copilot is
    # grounding on this connector rather than answering from general knowledge.
    $markerItem = @{
        id         = "restcountries-connector-marker"
        properties = @{
            name                 = "REST Countries connector grounding marker [APRIL2026]"
            region               = "Demo"
            subregion            = "Connector validation"
            capital              = "Not applicable"
            population           = 0
            latitude             = 0
            longitude            = 0
            areaInSqKm           = 0
            timezone             = "UTC"
            mapUrl               = "https://restcountries.com/"
            flagUrl              = "https://searchuxcdn.blob.core.windows.net/designerapp/images/DefaultMRTIcon.png"
            borders              = ""
            languages            = "Not applicable"
            currencies           = "Not applicable"
            lastModifiedBy       = "REST Countries"
            lastModifiedDateTime = $startDate
        }
        content    = @{
            value = "Internal country record Demo marker: RESTCOUNTRIES_CONNECTOR_2026."
            type  = 'text'
        }
        acl        = @(
            @{
                accessType = "grant"
                type       = "everyone"
                value      = "everyone"
            }
        )
        activities = @(@{
                "@odata.type" = "#microsoft.graph.externalConnectors.externalActivity"
                type          = "created"
                startDateTime = $startDate
                performedBy   = @{
                    type = "user"
                    id   = $UserId
                }
            })
    }

    try {
        Set-MgExternalConnectionItem -ExternalConnectionId $externalConnection.id `
        -ExternalItemId $markerItem.id `
        -BodyParameter $markerItem -ErrorAction Stop | Out-Null
        Write-Host "Imported grounding marker item..." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to import grounding marker item"
        Write-Error $_.Exception.Message
    }
}

# Build the connector schema and create or update the external connection
# before importing the REST Countries content.
# Register-CCApp `
#     -ConnectorDisplayName $connectorDisplayName `
#     -SecretName $secretName `
#     -ConfigPath $config

$schema = @(
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
<#
$externalConnection = New-CCConnection `
    -ConnectionId $connectorName `
    -ConnectionName $connectorDisplayName `
    -ConnectionDescription "Example Copilot connector created with PowerShell" `
    -ConnectionBaseUrls @("https://example.com") `
    -Schema $schema `
    -ResultLayoutPath (Join-Path $PSScriptRoot "resultLayout.json") `
    -SecretName $secretName `
    -ConfigPath $config `
    -Force

#>


# Retrieve the source data and ingest it into the connector.
$content = Get-RESTCountries -Url "https://restcountries.com/v3.1"
$externalConnection = Get-MgExternalConnection -ExternalConnectionId $connectorName -ErrorAction SilentlyContinue

Import-ExternalItems -Content $content -ExternalConnection $externalConnection -UserId $activityUserId
