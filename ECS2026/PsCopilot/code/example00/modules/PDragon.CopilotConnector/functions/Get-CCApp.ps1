function Get-CCApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ConnectorDisplayName
    )

    try {
        $graphScopes = @("Application.Read.All")
        $context = Get-MgContext
        if (-not $context -or $context.Scopes -notcontains "Application.Read.All") {
            Connect-MgGraph -Scopes $graphScopes -NoWelcome -UseDeviceCode -ContextScope Process
        }

        $escapedDisplayName = $ConnectorDisplayName -replace "'", "''"
        $apps = @(Get-MgApplication -Filter "displayName eq '$escapedDisplayName'")

        if ($apps.Count -eq 0) {
            Write-Warning "No Entra app registration found with display name '$ConnectorDisplayName'."
            return
        }

        $apps | Select-Object DisplayName, AppId, Id
    }
    catch {
        Write-Error "Get-CCApp failed: $_"
        throw
    }
}
