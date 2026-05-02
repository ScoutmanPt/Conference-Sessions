
# msg prefix
$prefix = "[CoPilot Connector][03-Import]:"

Write-Host "$($prefix) Import REST Countries content" -ForegroundColor Cyan
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

# Retrieve country data from the REST Countries API and normalize it for import.
function Get-RESTCountries {
  param(
    [string] $Url
  )

  Write-Host "$($prefix)  Preparing REST Countries import list..." -ForegroundColor Cyan
  $restCountries = @()

  # Request only the fields needed for the connector schema and result layout.
  $coreFields = "name,region,subregion,capital,population,latlng,area,timezones,maps,flags"
  $detailFields = "name,cca3,borders,languages,currencies"

  Write-Host "$($prefix)  Retrieving core country fields from $Url..." -ForegroundColor Cyan
  $json = Invoke-RestMethod -Uri "$Url/all?fields=$coreFields" -Method Get -ContentType "application/json"

  Write-Host "$($prefix)  Retrieving country detail fields from $Url..." -ForegroundColor Cyan
  $details = Invoke-RestMethod -Uri "$Url/all?fields=$detailFields" -Method Get -ContentType "application/json"

  # Build lookup tables so border country codes can be converted to country names.
  $detailsByName = @{}
  $countryNamesByCode = @{}

  Write-Host "$($prefix)  Building country lookup tables..." -ForegroundColor Cyan
  $details | ForEach-Object {
    $detailsByName[$_.name.common] = $_
    $countryNamesByCode[$_.cca3] = $_.name.common
  }

  $index = 1

  # Convert API responses into the property names expected by the connector schema.
  $json | ForEach-Object {
    $country = $_
    $countryDetails = $detailsByName[$country.name.common]

    # Convert border country codes into readable country names.
    $borderCountries = @($countryDetails.borders | ForEach-Object {
        if ($countryNamesByCode.ContainsKey($_)) {
          $countryNamesByCode[$_]
        }
      })

    Write-Host "$($prefix)  Retrieving $($country.name.common)... $index of $($json.Count)" -ForegroundColor Cyan

    # Create a normalized country object and add it to the import list.
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

# Import normalized country records into the Microsoft Graph external connection.
function Import-ExternalItems {
  param(
    [Object[]] $Content
  )
  # Read the app-only credential created by 01-Initialize-EntraApp.ps1.
  Write-Host "$($prefix)  Reading app-only credential from SecretManagement secret '$secretName'..." -ForegroundColor Cyan
  $tenantId = $global:mainApp.TenantId
  $secretName = $global:mainApp.SecretName
  $credential = Get-Secret -Name $secretName

  # Connect to Microsoft Graph with the connector app registration.
  Write-Host "$($prefix)  Connecting to Microsoft Graph with app-only credentials..." -ForegroundColor Cyan
  Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
  Connect-MgGraph -ClientSecretCredential $credential -TenantId $tenantId -NoWelcome -ContextScope Process

  Write-Host "$($prefix)  Preparing external items for import..." -ForegroundColor Cyan
  $startDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"

  $index = 1
  # Initialize to an empty variable to make sure the same are loaded in configuration script and connection initialization script
  $externalConnection = $null
  . $PSScriptRoot\Get-ConnConfiguration.ps1
  # Save the normalized content locally so the import payload can be validated.
  Write-Host "$($prefix)  Writing validation data to restcountries-content.json..." -ForegroundColor Cyan
  $Content | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $PSScriptRoot "restcountries-content.json") -Encoding utf8
  
  # Create and import one external item per country.
  Write-Host "$($prefix)  Importing $($Content.Count) country items into Microsoft Graph..." -ForegroundColor Cyan
  $Content | ForEach-Object {
    # Build the external item body expected by Set-MgExternalConnectionItem.
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

      # Add a created activity so the item has an activity signal in Graph.
      activities = @(@{
          "@odata.type" = "#microsoft.graph.externalConnectors.externalActivity"
          type          = "created"
          startDateTime = $startDate
          performedBy   = @{
            type = "user"
            id   = $externalConnection.userId
          }
        })
    }

    try {
      Set-MgExternalConnectionItem -ExternalConnectionId $externalConnection.connection.id -ExternalItemId $item.id -BodyParameter $item -ErrorAction Stop | Out-Null
      
      Write-Host "$($prefix)  Imported $($item.properties.name)... $index of $($Content.Count)" -ForegroundColor Cyan  
    }
    catch {
      Write-Error "Failed to import $($item.properties.name)"
      Write-Error $_.Exception.Message
    }
    
    $index++
  }

  # Import a marker item to indicate the source of the data and support grounding validation.
  Write-Host "$($prefix)  Preparing grounding marker item..." -ForegroundColor Cyan
  $markerItem = @{
    id         = "restcountries-connector-marker"
    properties = @{
      name                 = "REST Countries connector grounding marker"
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
          id   = $externalConnection.userId
        }
      })
  }

  try {
    Write-Host "$($prefix)  Importing grounding marker item..." -ForegroundColor Cyan
    Set-MgExternalConnectionItem -ExternalConnectionId $externalConnection.connection.id -ExternalItemId $markerItem.id -BodyParameter $markerItem -ErrorAction Stop | Out-Null
    Write-Host "$($prefix)  Imported grounding marker item..." -ForegroundColor Green
  }
  catch {
    Write-Error "Failed to import grounding marker item"
    Write-Error $_.Exception.Message
  }
}

# Retrieve the REST Countries source data and import it into the external connection.
Write-Host "$($prefix)  Starting REST Countries retrieval..." -ForegroundColor Cyan
$content = Get-RESTCountries -Url "https://restcountries.com/v3.1"

Write-Host "$($prefix)  Starting Microsoft Graph external item import..." -ForegroundColor Cyan
Import-ExternalItems -Content $content
Write-Host "$($prefix)Content import completed" -ForegroundColor Cyan
