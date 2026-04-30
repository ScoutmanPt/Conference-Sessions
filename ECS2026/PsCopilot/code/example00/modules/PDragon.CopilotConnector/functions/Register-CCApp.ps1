function Register-CCApp {
<#
.SYNOPSIS
    Registers a new Entra app for a Microsoft Copilot connector.

.DESCRIPTION
    Creates an Entra ID (Azure AD) app registration with the required Microsoft Graph
    application permissions (ExternalConnection.ReadWrite.OwnedBy and
    ExternalItem.ReadWrite.OwnedBy), creates a service principal, assigns app roles,
    generates a client secret, stores it in a SecretManagement vault, and writes
    TenantId and ClientId to a config.ini file.

    If an app with the same display name already exists, the user is prompted to
    confirm deletion before recreating.

.PARAMETER ConnectorDisplayName
    The display name for the Entra app registration. Defaults to 'Copilot Connector'.

.PARAMETER SecretName
    The name used to store the PSCredential (AppId + secret) in the SecretManagement
    vault. Defaults to 'secretnamepowershell'.

.PARAMETER ConfigPath
    Full path to the config.ini file where TenantId and ClientId will be written.
    The parent directory must already exist.

.OUTPUTS
    [pscustomobject] with AppId, ObjectId, DisplayName, SecretName, and ConfigPath.

.EXAMPLE
    Register-CCApp -ConnectorDisplayName 'My Connector' -SecretName 'myconnpowershell' -ConfigPath 'C:\connectors\config.ini'
#>
    [CmdletBinding()]
    param(
        [string] $ConnectorDisplayName = "Copilot Connector",
        [string] $SecretName = "secretnamepowershell",
        [string] $ConfigPath 
    )

    if ([string]::IsNullOrWhiteSpace($ConnectorDisplayName)) { throw "ConnectorDisplayName cannot be empty." }
    if ([string]::IsNullOrWhiteSpace($ConfigPath))            { throw "ConfigPath cannot be empty." }
    if (-not (Test-Path (Split-Path $ConfigPath -Parent)))    { throw "ConfigPath parent directory does not exist: $(Split-Path $ConfigPath -Parent)" }

    $permExternalConnectionReadWrite = "f431331c-49a6-499f-be1c-62af19c34a9d"
    $permExternalItemReadWrite = "8116ae0f-55c2-452d-9944-d18420f5b2c8"
    $msGraphAppId = "00000003-0000-0000-c000-000000000000"

    $graphScopes = @(
        "AppRoleAssignment.ReadWrite.All"
        "Application.ReadWrite.All"
        "Application.Read.All"
    )

    try {
        Write-Host ""
        Write-Host "Registering a new Copilot Connector App ---" -ForegroundColor White
        Write-Host "  ConnectorDisplayName : '$ConnectorDisplayName'" -ForegroundColor White
        Write-Host "  SecretName           : '$SecretName'" -ForegroundColor White
        Write-Host "  ConfigPath           : '$ConfigPath'" -ForegroundColor White
        Write-Host ""
        Write-Host "  [1/7] Connecting to Microsoft Graph..." -ForegroundColor Cyan
        $context = Get-MgContext
        $hasRequiredScopes = $context -and @($graphScopes | Where-Object { $context.Scopes -notcontains $_ }).Count -eq 0
        if (-not $hasRequiredScopes) {
            Connect-MgGraph -Scopes $graphScopes -NoWelcome -UseDeviceCode -ContextScope Process
        }

        Write-Host "  [2/7] Checking for existing app registrations..." -ForegroundColor Cyan
        $escapedDisplayName = $ConnectorDisplayName -replace "'", "''"
        $existingApps = @(Get-MgApplication -Filter "displayName eq '$($escapedDisplayName)'")

        if ($existingApps.Count -gt 0) {
            Write-Host ""
            Write-Warning "Found $($existingApps.Count) existing Entra app registration(s) named '$ConnectorDisplayName'."
            $existingApps | Select-Object DisplayName, AppId, Id | Format-Table -AutoSize

            $choice = Read-Host "Type DELETE to remove the existing app registration(s) and recreate, or press Enter to exit"
            Write-Host ""

            if ($choice -ne "DELETE") {
                Write-Host "No changes made. Exiting." -ForegroundColor Yellow
                return
            }

            Write-Host "  [2/7] Removing existing app registration(s)..." -ForegroundColor Cyan
            foreach ($existingApp in $existingApps) {
                $existingServicePrincipals = @(Get-MgServicePrincipal -Filter "appId eq '$($existingApp.AppId)'")

                foreach ($existingServicePrincipal in $existingServicePrincipals) {
                    Remove-MgServicePrincipal -ServicePrincipalId $existingServicePrincipal.Id -Confirm:$false -ErrorAction SilentlyContinue
                }

                Remove-MgApplication -ApplicationId $existingApp.Id -Confirm:$false -ErrorAction Stop
            }
        }

        # --- Create app registration ---
        Write-Host "  [3/7] Creating app registration '$ConnectorDisplayName'..." -ForegroundColor Cyan
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

        # --- Create service principal ---
        Write-Host "  [4/7] Creating service principal..." -ForegroundColor Cyan
        $graphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$($msGraphAppId)'"
        $connectorServicePrincipal = New-MgServicePrincipal -AppId $app.AppId

        # --- Assign app roles ---
        Write-Host "  [5/7] Assigning app roles..." -ForegroundColor Cyan
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $connectorServicePrincipal.Id -PrincipalId $connectorServicePrincipal.Id -AppRoleId $permExternalConnectionReadWrite -ResourceId $graphServicePrincipal.Id | Out-Null
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $connectorServicePrincipal.Id -PrincipalId $connectorServicePrincipal.Id -AppRoleId $permExternalItemReadWrite -ResourceId $graphServicePrincipal.Id | Out-Null

        # --- Store client secret ---
        Write-Host "  [6/7] Storing client secret in SecretManagement vault..." -ForegroundColor Cyan
        $passwordCredential = Add-MgApplicationPassword -ApplicationId $app.Id
        $secureSecret = ConvertTo-SecureString -String $passwordCredential.SecretText -AsPlainText -Force
        $credential = [pscredential]::new($app.AppId, $secureSecret)

        Write-Host ""
        Set-Secret -Name $SecretName -Secret $credential
        Write-Host ""

        # --- Write config.ini ---
        Write-Host "  [7/7] Writing config.ini..." -ForegroundColor Cyan
        $configLines = @(
            "TenantId=$((Get-MgContext).TenantId)"
            "ClientId=$($app.AppId)"
        )

        $config = $configLines -join [Environment]::NewLine
        $config | Out-File -FilePath $ConfigPath -Encoding utf8

        Write-Host ""
        Write-Host "Copilot Connector App [$($ConnectorDisplayName)] registered !" -ForegroundColor White
        [pscustomobject]@{
            AppId       = $app.AppId
            ObjectId    = $app.Id
            DisplayName = $app.DisplayName
            SecretName  = $SecretName
            ConfigPath  = $ConfigPath
        }
    }
    catch {
        Write-Error "Register-CCApp failed: $_"
        throw
    }
}
