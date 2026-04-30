function Get-CCApp {
<#
.SYNOPSIS
    Retrieves Entra app registrations for a Copilot connector by display name.

.DESCRIPTION
    Searches Microsoft Entra ID (Azure AD) for app registrations matching the given
    display name. Connects to Microsoft Graph with Application.Read.All scope if the
    current context does not already have it.

.PARAMETER ConnectorDisplayName
    The display name of the Entra app registration to look up.

.OUTPUTS
    Selected properties (DisplayName, AppId, Id) for each matching app registration.

.EXAMPLE
    Get-CCApp -ConnectorDisplayName 'My Copilot Connector'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ConnectorDisplayName
    )

    try {
        # --- Graph connection ---
        $graphScopes = @("Application.Read.All")
        $context = Get-MgContext
        if (-not $context -or $context.Scopes -notcontains "Application.Read.All") {
            Connect-MgGraph -Scopes $graphScopes -NoWelcome -UseDeviceCode -ContextScope Process
        }

        # --- Query app registrations ---
        $escapedDisplayName = $ConnectorDisplayName -replace "'", "''"
        $apps = @(Get-MgApplication -Filter "displayName eq '$escapedDisplayName'")

        if ($apps.Count -eq 0) {
            Write-Warning "No Entra app registration found with display name '$ConnectorDisplayName'."
            return
        }

        # --- Return results ---
        $apps | Select-Object DisplayName, AppId, Id
    }
    catch {
        Write-Error "Get-CCApp failed: $_"
        throw
    }
}
