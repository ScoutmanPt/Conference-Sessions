function Unregister-CCApp {
<#
.SYNOPSIS
    Removes an Entra app registration and its service principals for a Copilot connector.

.DESCRIPTION
    Finds all Entra ID app registrations matching the given display name, then deletes
    their service principals and the app registrations themselves. Supports -WhatIf
    and -Confirm (ConfirmImpact = High) to prevent accidental deletion.

.PARAMETER ConnectorDisplayName
    The display name of the Entra app registration(s) to remove.

.EXAMPLE
    Unregister-CCApp -ConnectorDisplayName 'My Copilot Connector'

.EXAMPLE
    Unregister-CCApp -ConnectorDisplayName 'My Copilot Connector' -WhatIf
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string] $ConnectorDisplayName
    )

    # --- Required Graph scopes ---
    $graphScopes = @(
        "Application.ReadWrite.All"
        "AppRoleAssignment.ReadWrite.All"
    )

    try {
        # --- Graph connection ---
        $context = Get-MgContext
        $hasRequiredScopes = $context -and ($graphScopes | Where-Object { $context.Scopes -notcontains $_ }).Count -eq 0
        if (-not $hasRequiredScopes) {
            Connect-MgGraph -Scopes $graphScopes -NoWelcome -UseDeviceCode -ContextScope Process
        }

        # --- Find matching app registrations ---
        $escapedDisplayName = $ConnectorDisplayName -replace "'", "''"
        $apps = @(Get-MgApplication -Filter "displayName eq '$escapedDisplayName'")

        if ($apps.Count -eq 0) {
            Write-Warning "No Entra app registration found with display name '$ConnectorDisplayName'."
            return
        }

        # --- Delete each app and its service principals ---
        foreach ($app in $apps) {
            if ($PSCmdlet.ShouldProcess("$($app.DisplayName) ($($app.AppId))", "Delete Entra app registration")) {
                $servicePrincipals = @(Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'")
                foreach ($sp in $servicePrincipals) {
                    Remove-MgServicePrincipal -ServicePrincipalId $sp.Id -Confirm:$false #-ErrorAction SilentlyContinue
                }

                Remove-MgApplication -ApplicationId $app.Id -Confirm:$false -ErrorAction Stop
                Write-Host "Deleted app registration '$($app.DisplayName)' ($($app.AppId))." -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Error "Unregister-CCApp failed: $_"
        throw
    }
}
