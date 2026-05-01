function Register-CCApp {
<#
.SYNOPSIS
    Registers a new Entra app for a Microsoft Copilot connector.

.DESCRIPTION
    Creates an Entra ID (Azure AD) app registration with the required Microsoft Graph
    application permissions (ExternalConnection.ReadWrite.OwnedBy and
    ExternalItem.ReadWrite.OwnedBy), creates a service principal, assigns app roles,
    generates a client secret, stores it in a SecretManagement vault, and returns
    the TenantId and AppId needed by New-CCConnection. If ConfigPath is supplied,
    TenantId and ClientId are also written to a config.ini file.

    If an app with the same display name already exists, the user is prompted to
    confirm deletion before recreating.

.PARAMETER ConnectorDisplayName
    The display name for the Entra app registration. Defaults to 'Copilot Connector'.

.PARAMETER SecretName
    The name used to store the PSCredential (AppId + secret) in the SecretManagement
    vault. Defaults to 'secretnamepowershell'.

.PARAMETER ConfigPath
    Optional full path to the config.ini file where TenantId and ClientId will be
    written. The parent directory must already exist when supplied.

.OUTPUTS
    [pscustomobject] with TenantId, AppId, ObjectId, DisplayName, SecretName, and ConfigPath.

.EXAMPLE
    $app = Register-CCApp -ConnectorDisplayName 'My Connector' -SecretName 'myconnpowershell'
    New-CCConnection -TenantId $app.TenantId -AppId $app.AppId ...
#>
    [CmdletBinding()]
    param(
        [string] $ConnectorDisplayName = "Copilot Connector",
        [string] $SecretName = "secretnamepowershell",
        [string] $ConfigPath 
    )

    if ([string]::IsNullOrWhiteSpace($ConnectorDisplayName)) { throw "ConnectorDisplayName cannot be empty." }
    if ((-not [string]::IsNullOrWhiteSpace($ConfigPath)) -and (-not (Test-Path (Split-Path $ConfigPath -Parent)))) {
        throw "ConfigPath parent directory does not exist: $(Split-Path $ConfigPath -Parent)"
    }

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
        if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
            Write-Host "  ConfigPath           : '$ConfigPath'" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "  [1/7] Connecting to Microsoft Graph ......" -ForegroundColor Cyan
        # $context = Get-MgContext
        # $hasRequiredScopes = $context -and @($graphScopes | Where-Object { $context.Scopes -notcontains $_ }).Count -eq 0
        # if (-not $hasRequiredScopes) {
        Connect-MgGraph -Scopes $graphScopes -NoWelcome -ContextScope Process
        # }

        $tenantId = (Get-MgContext).TenantId

        if ([string]::IsNullOrWhiteSpace($tenantId)) {
            throw "Could not determine TenantId from the current Microsoft Graph context."
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
                    Remove-MgServicePrincipal -ServicePrincipalId $existingServicePrincipal.Id -Confirm:$false #-ErrorAction SilentlyContinue
                }

                Remove-MgApplication -ApplicationId $existingApp.Id -Confirm:$false -ErrorAction Stop
            }

            Write-Host "       Existing app secret entry '$SecretName' will be replaced when the new credential is stored." -ForegroundColor Cyan
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
        $storedCredential = Get-Secret -Name $SecretName -ErrorAction Stop

        if ($storedCredential -is [securestring]) {
            $storedCredential = [pscredential]::new($app.AppId, $storedCredential)
        }

        if ($storedCredential -isnot [pscredential] -or $storedCredential.UserName -ne $app.AppId) {
            throw "Secret '$SecretName' was not persisted with the expected client id '$($app.AppId)'."
        }
        Write-Host ""

        # --- Optional config.ini output ---
        if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
            Write-Host "  [7/7] Writing config.ini..." -ForegroundColor Cyan
            $configLines = @(
                "TenantId=$tenantId"
                "ClientId=$($app.AppId)"
            )

            $config = $configLines -join [Environment]::NewLine
            $config | Out-File -FilePath $ConfigPath -Encoding utf8
        }
        else {
            Write-Host "  [7/7] Returning tenant and app identifiers..." -ForegroundColor Cyan
        }

        # App-only auth can take a short while to start working after the app,
        # service principal, roles, and secret have just been created.
        Write-Host "       Verifying app-only authentication..." -ForegroundColor Cyan -NoNewline
        $verified = $false
        $retryCount = 0
        $lastAuthError = $null

        Start-Sleep -Seconds 5

        while (-not $verified) {
            try {
                $retryCount++
                Disconnect-MgGraph #-ErrorAction SilentlyContinue | Out-Null
                Connect-MgGraph -ClientSecretCredential $credential -TenantId $tenantId -NoWelcome -ContextScope Process -ErrorAction Stop
                $verified = $true
            }
            catch {
                $lastAuthError = $_.Exception.Message
                if ([string]::IsNullOrWhiteSpace($lastAuthError)) {
                    $lastAuthError = $_ | Out-String
                }

                if ($retryCount -eq 1 -or ($retryCount % 6) -eq 0) {
                    Write-Host ""
                    Write-Host "       Waiting for app-only authentication to become available..." -ForegroundColor Yellow
                    Write-Host "       Last authentication error: $lastAuthError" -ForegroundColor DarkYellow
                    Write-Host "       TenantId: $tenantId" -ForegroundColor DarkYellow
                    Write-Host "       ClientId: $($app.AppId)" -ForegroundColor DarkYellow
                }

                Start-Sleep -Seconds 10
                Write-Host "." -NoNewline -ForegroundColor Cyan
            }
        }

        Write-Host ""

        Write-Host ""
        Write-Host "Copilot Connector App [$($ConnectorDisplayName)] registered !" -ForegroundColor White
        [pscustomobject]@{
            TenantId    = $tenantId
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
