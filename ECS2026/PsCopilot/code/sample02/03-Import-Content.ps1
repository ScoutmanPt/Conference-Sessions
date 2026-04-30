. (Join-Path $PSScriptRoot "Initialize-GraphClient.ps1")
. (Join-Path $PSScriptRoot "ConnectionConfiguration.ps1")


function Get-RESTCountries {
  param(
    [string] $Url
  )

  $restCountries = @()

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

function Import-ExternalItems {
  param(
    [Object[]] $Content
  )

  $startDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"

  $index = 1
  ##sve Content as a json file
  $Content | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $PSScriptRoot "restcountries-content.json") -Encoding utf8
  $Content | ForEach-Object {
    $item = @{
      id         = $index
      properties = @{
        name       = $_.Name
        region     = $_.Region
        subregion  = $_.Subregion
        capital    = $_.Capital
        population = $_.Population
        latitude   = $_.Latitude
        longitude  = $_.Longitude
        areaInSqKm = $_.AreaInSqKm
        timezone   = $_.Timezone
        mapUrl     = [System.Uri]::new($_.Map).ToString()
        flagUrl    = [System.Uri]::new($_.Flag).ToString()
        borders    = $_.Borders
        languages  = $_.Languages
        currencies = $_.Currencies
        lastModifiedBy = "REST Countries"
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
            id   = $externalConnection.userId
          }
        })
    }

    try {
      Set-MgExternalConnectionItem -ExternalConnectionId $externalConnection.connection.id -ExternalItemId $item.id -BodyParameter $item -ErrorAction Stop | Out-Null
      
      Write-Host "Imported $($item.properties.name)... $index of $($Content.Count)" -ForegroundColor Green  
    }
    catch {
      Write-Error "Failed to import $($item.properties.name)"
      Write-Error $_.Exception.Message
    }
    
    $index++
  }

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
    Set-MgExternalConnectionItem -ExternalConnectionId $externalConnection.connection.id -ExternalItemId $markerItem.id -BodyParameter $markerItem -ErrorAction Stop | Out-Null
    Write-Host "Imported grounding marker item..." -ForegroundColor Green
  }
  catch {
    Write-Error "Failed to import grounding marker item"
    Write-Error $_.Exception.Message
  }
}

$content = Get-RESTCountries -Url "https://restcountries.com/v3.1"
Import-ExternalItems -Content $content
