function Register-CCApp {
    [CmdletBinding()]
    param(
        [string] $ConnectorDisplayName = "Copilot Connector",
        [string] $SecretName = "testconnpowershell",
        [string] $ConfigPath 
    )

    $permExternalConnectionReadWrite = "f431331c-49a6-499f-be1c-62af19c34a9d"
    $permExternalItemReadWrite = "8116ae0f-55c2-452d-9944-d18420f5b2c8"
    $msGraphAppId = "00000003-0000-0000-c000-000000000000"

    $graphScopes = @(
        "AppRoleAssignment.ReadWrite.All"
        "Application.ReadWrite.All"
    )

    Connect-MgGraph -Scopes $graphScopes -NoWelcome -UseDeviceCode -ContextScope Process

    $escapedDisplayName = $ConnectorDisplayName -replace "'", "''"
    $existingApps = @(Get-MgApplication -Filter "displayName eq '$escapedDisplayName'")

    if ($existingApps.Count -gt 0) {
        Write-Warning "Found $($existingApps.Count) existing Entra app registration(s) named '$ConnectorDisplayName'."
        $existingApps | Select-Object DisplayName, AppId, Id | Format-Table -AutoSize

        $choice = Read-Host "Type DELETE to remove the existing app registration(s) and recreate, or press Enter to exit"

        if ($choice -ne "DELETE") {
            Write-Host "No changes made. Exiting." -ForegroundColor Yellow
            return
        }

        foreach ($existingApp in $existingApps) {
            $existingServicePrincipals = @(Get-MgServicePrincipal -Filter "appId eq '$($existingApp.AppId)'")

            foreach ($existingServicePrincipal in $existingServicePrincipals) {
                Remove-MgServicePrincipal -ServicePrincipalId $existingServicePrincipal.Id -Confirm:$false -ErrorAction SilentlyContinue
            }

            Remove-MgApplication -ApplicationId $existingApp.Id -Confirm:$false -ErrorAction Stop
        }
    }

    $requiredResourceAccess = @(
        @{
            resourceAppId  = $msGraphAppId
            resourceAccess = @(
                @{
                    id   = $permExternalConnectionReadWrite
                    type = "Role"
                }
                @{
                    id   = $permExternalItemReadWrite
                    type = "Role"
                }
            )
        }
    )

    $app = New-MgApplication -DisplayName $ConnectorDisplayName -RequiredResourceAccess $requiredResourceAccess
    $graphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$($msGraphAppId)'"
    $connectorServicePrincipal = New-MgServicePrincipal -AppId $app.AppId

    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $connectorServicePrincipal.Id -PrincipalId $connectorServicePrincipal.Id -AppRoleId $permExternalConnectionReadWrite -ResourceId $graphServicePrincipal.Id | Out-Null
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $connectorServicePrincipal.Id -PrincipalId $connectorServicePrincipal.Id -AppRoleId $permExternalItemReadWrite -ResourceId $graphServicePrincipal.Id | Out-Null

    $passwordCredential = Add-MgApplicationPassword -ApplicationId $app.Id
    $secureSecret = ConvertTo-SecureString -String $passwordCredential.SecretText -AsPlainText -Force
    $credential = [pscredential]::new($app.AppId, $secureSecret)

    Set-Secret -Name $SecretName -Secret $credential

    $configLines = @(
        "TenantId=$((Get-MgContext).TenantId)"
        "ClientId=$($app.AppId)"
    )

    $config = $configLines -join [Environment]::NewLine
    $config | Out-File -FilePath $ConfigPath -Encoding utf8

    [pscustomobject]@{
        AppId      = $app.AppId
        ObjectId   = $app.Id
        DisplayName = $app.DisplayName
        SecretName = $SecretName
        ConfigPath = $ConfigPath
    }
}
