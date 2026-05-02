# Load the schema property helper when this script is run directly.
Write-Host "$($prefix)  Loading schema property helper..." -ForegroundColor Cyan
if (-not (Get-Command New-CCProperty -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "../_helpers/New-CCProperty.ps1")
}
[hashtable]$adaptiveCard = @{}
$adaptiveCard += Get-Content -Path (Join-Path $PSScriptRoot "resultLayout.json") -Raw | ConvertFrom-Json -AsHashtable

$searchTemplateId = $global:mainApp.Id.Substring(0, [Math]::Min($global:mainApp.Id.Length, 16))
# Build the external connection payload and schema definition.
Write-Host "$($prefix)  Building external connection payload..." -ForegroundColor Cyan
$externalConnection = @{
    userId     = "e1251b10-1ba4-49e3-b35a-933e3f21772b"
    connection = @{
        id               = $global:mainApp.Id
        name             = $global:mainApp.DisplayName
        description      = $global:mainApp.Description
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