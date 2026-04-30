function Set-CCConfiguration {
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
        [string] $ResultLayoutPath = (Join-Path $PSScriptRoot "assets/resultLayout.json"),
        [string] $UserId = [guid]::NewGuid().ToString()
    )

    if (-not (Test-Path $ResultLayoutPath)) { throw "ResultLayoutPath not found at: $ResultLayoutPath" }

    try {
    # Initialize to an empty hashtable to explicitly define the type as hashtable.
    # This is needed to avoid the breaking change introduced in PowerShell 7.3 - https://github.com/PowerShell/PowerShell/issues/18524.
    # https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/2352
    [hashtable]$adaptiveCard = @{}
    $adaptiveCard += Get-Content -Path $ResultLayoutPath -Raw | ConvertFrom-Json -AsHashtable

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
