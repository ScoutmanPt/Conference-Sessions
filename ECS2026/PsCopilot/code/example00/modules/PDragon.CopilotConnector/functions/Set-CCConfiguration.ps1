function Set-CCConfiguration {
<#
.SYNOPSIS
    Builds the external connection configuration hashtable for a Copilot connector.

.DESCRIPTION
    Assembles the full connection configuration object including connection metadata,
    URL-to-item resolver activity settings, search result template (adaptive card
    layout loaded from a JSON file), and the schema property array. The returned
    hashtable is used as input for New-CCConnection.

.PARAMETER ConnectionId
    The unique identifier for the external connection (lowercase, no spaces).

.PARAMETER ConnectionName
    The human-readable display name shown in the Microsoft Search admin center.

.PARAMETER ConnectionDescription
    A description of the connector shown in the Microsoft Search admin center.

.PARAMETER ConnectionBaseUrls
    One or more base URLs used by the URL-to-item resolver activity settings.

.PARAMETER Schema
    Array of property hashtables built with New-CCProperty.

.PARAMETER ResultLayoutPath
    Path to the adaptive card JSON file used as the search result template.
    Defaults to the assets/resultLayout.json file in the module directory.

.PARAMETER UserId
    Optional user ID associated with the connection. Defaults to a new GUID.

.OUTPUTS
    [hashtable] Full connection configuration with keys: userId, connection, schema.

.EXAMPLE
    $config = Set-CCConfiguration -ConnectionId 'myconn' -ConnectionName 'My Conn' `
        -ConnectionDescription 'Demo connector' -ConnectionBaseUrls @('https://example.com') `
        -Schema $schema -ResultLayoutPath '.\assets\resultLayout.json'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ConnectionId,
        [Parameter(Mandatory)]
        [string] $ConnectionName,
        [Parameter(Mandatory)]
        [string] $ConnectionDescription,
        [Parameter(Mandatory)]
        [string[]] $ConnectionBaseUrls,
        [Parameter(Mandatory)]
        [hashtable[]] $Schema,
        [string] $ResultLayoutPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../assets/resultLayout.json")),
        [string] $UserId = [guid]::NewGuid().ToString()
    )

    # --- Parameter validation ---
    if (-not (Test-Path $ResultLayoutPath)) { throw "ResultLayoutPath not found at: $ResultLayoutPath" }

    try {
    # --- Load adaptive card layout ---
    # Initialize to an empty hashtable to explicitly define the type as hashtable.
    # This is needed to avoid the breaking change introduced in PowerShell 7.3 - https://github.com/PowerShell/PowerShell/issues/18524.
    # https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/2352
    [hashtable]$adaptiveCard = @{}
    $adaptiveCard += Get-Content -Path $ResultLayoutPath -Raw | ConvertFrom-Json -AsHashtable

    # --- Assemble connection configuration ---
    @{
        userId     = $UserId
        connection = @{
            id               = $ConnectionId
            name             = $ConnectionName
            description      = $ConnectionDescription
            activitySettings = @{
                urlToItemResolvers = @(
                    @{
                        "@odata.type" = "#microsoft.graph.externalConnectors.itemIdResolver"
                        urlMatchInfo  = @{
                            baseUrls   = $ConnectionBaseUrls
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
                        id       = $ConnectionId
                        priority = 1
                        layout   = @{
                            additionalProperties = $adaptiveCard
                        }
                    }
                )
            }
        }
        
        schema     = $Schema
    }
    }
    catch {
        Write-Error "Set-CCConfiguration failed: $_"
        throw
    }
}
