function Unregister-CCApp {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string] $ConnectorDisplayName
    )

    $graphScopes = @(
        "Application.ReadWrite.All"
        "AppRoleAssignment.ReadWrite.All"
    )

    Connect-MgGraph -Scopes $graphScopes -NoWelcome -UseDeviceCode -ContextScope Process

    $escapedDisplayName = $ConnectorDisplayName -replace "'", "''"
    $apps = @(Get-MgApplication -Filter "displayName eq '$escapedDisplayName'")

    if ($apps.Count -eq 0) {
        Write-Warning "No Entra app registration found with display name '$ConnectorDisplayName'."
        return
    }

    foreach ($app in $apps) {
        if ($PSCmdlet.ShouldProcess("$($app.DisplayName) ($($app.AppId))", "Delete Entra app registration")) {
            $servicePrincipals = @(Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'")
            foreach ($sp in $servicePrincipals) {
                Remove-MgServicePrincipal -ServicePrincipalId $sp.Id -Confirm:$false -ErrorAction SilentlyContinue
            }

            Remove-MgApplication -ApplicationId $app.Id -Confirm:$false -ErrorAction Stop
            Write-Host "Deleted app registration '$($app.DisplayName)' ($($app.AppId))." -ForegroundColor Green
        }
    }
}
