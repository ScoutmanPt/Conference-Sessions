function New-CCConnection {
<#
.SYNOPSIS
    Creates or updates a Microsoft Graph external connection for a Copilot connector.

.DESCRIPTION
    Reads credentials from a SecretManagement vault, connects to Microsoft Graph
    with the supplied tenant id and app id, then recreates the external connection
    and its schema. If a connection with the same id already exists, it is deleted
    first. Waits for schema provisioning to complete before returning. Optionally
    enables Copilot visibility (search content experience) on the connection.

.PARAMETER ConnectionId
    The unique identifier for the external connection (lowercase letters and digits,
    no spaces). Must be unique within the tenant.

.PARAMETER ConnectionName
    The human-readable display name shown in the Microsoft Search admin center.

.PARAMETER ConnectionDescription
    A short description of the connector shown in the Microsoft Search admin center.

.PARAMETER ConnectionBaseUrls
    One or more base URLs used by the URL-to-item resolver activity settings
    (e.g. @('https://example.com')).

.PARAMETER Schema
    Array of property hashtables built with New-CCProperty that define the schema
    for external items ingested into this connection.

.PARAMETER ResultLayoutPath
    Full path to the adaptive card JSON file used as the search result template.

.PARAMETER SecretName
    Name of the SecretManagement secret that stores the PSCredential (AppId as
    username, client secret as password). Defaults to 'secretnamepowershell'.

.PARAMETER TenantId
    The Entra tenant id used for app-only Microsoft Graph authentication.

.PARAMETER AppId
    The client/application id used for app-only Microsoft Graph authentication.

.PARAMETER SkipCopilotVisibility
    Skips the step that enables the 'search' content experience on the connection.

.EXAMPLE
    New-CCConnection -ConnectionId 'myconn' -ConnectionName 'My Connector' `
        -ConnectionDescription 'Demo connector' `
        -ConnectionBaseUrls @('https://example.com') `
        -Schema $schema `
        -ResultLayoutPath '.\assets\resultLayout.json' `
        -SecretName 'myconnpowershell' `
        -TenantId '00000000-0000-0000-0000-000000000000' `
        -AppId '11111111-1111-1111-1111-111111111111'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ConnectionId,
        [Parameter(Mandatory)] [string] $ConnectionName,
        [Parameter(Mandatory)] [string] $ConnectionDescription,
        [Parameter(Mandatory)] [string[]] $ConnectionBaseUrls,
        [Parameter(Mandatory)] [hashtable[]] $Schema,
        [Parameter(Mandatory)] [string] $ResultLayoutPath,
        [Parameter(Mandatory)] [string] $TenantId,
        [Parameter(Mandatory)] [string] $AppId,
        [string] $SecretName = "secretnamepowershell",
        [switch] $SkipCopilotVisibility
    )

    # --- Parameter validation ---
    if (-not (Test-Path $ResultLayoutPath))           { throw "ResultLayoutPath not found at: $ResultLayoutPath" }
    if ([string]::IsNullOrWhiteSpace($TenantId))       { throw "TenantId cannot be empty." }
    if ([string]::IsNullOrWhiteSpace($AppId))          { throw "AppId cannot be empty." }

    try {
    Write-Host ""
    Write-Host "Creating new Copilot connector connection ---" -ForegroundColor White
    Write-Host ""
    Write-Host "  ConnectionId          : '$ConnectionId'" -ForegroundColor White
    Write-Host "  ConnectionName        : '$ConnectionName'" -ForegroundColor White
    Write-Host "  ConnectionDescription : '$ConnectionDescription'" -ForegroundColor White
    Write-Host "  ConnectionBaseUrls    : '$($ConnectionBaseUrls -join ', ')'" -ForegroundColor White
    Write-Host "  TenantId              : '$TenantId'" -ForegroundColor White
    Write-Host "  AppId                 : '$AppId'" -ForegroundColor White
    Write-Host "  SecretName            : '$SecretName'" -ForegroundColor White
    Write-Host "  ResultLayoutPath      : '$ResultLayoutPath'" -ForegroundColor White
    Write-Host ""

    Write-Host "  [1/6] Reading credentials..." -ForegroundColor Cyan
    Write-Host ""
    $credential = Get-Secret -Name $SecretName

    if ($credential -is [securestring]) {
        $credential = [pscredential]::new($AppId, $credential)
    }

    if ($credential -isnot [pscredential] -or [string]::IsNullOrWhiteSpace($credential.UserName)) {
        throw "Secret '$SecretName' must contain a PSCredential with the client ID as username and client secret as password."
    }

    if ($credential.UserName -ne $AppId) {
        throw "Secret '$SecretName' contains client id '$($credential.UserName)', but AppId parameter contains '$AppId'. Re-run Register-CCApp or pass the AppId that matches the stored secret."
    }

    Write-Host "  [2/6] Connecting to Microsoft Graph..." -ForegroundColor Cyan
    $mgReady      = $false
    $mgRetryCount = 0
    while (-not $mgReady) {
        try {
            $mgRetryCount++
            Disconnect-MgGraph #-ErrorAction SilentlyContinue | Out-Null
            Connect-MgGraph -ClientSecretCredential $credential -TenantId $TenantId -NoWelcome -ContextScope Process -ErrorAction Stop
            Get-MgExternalConnection -Top 1 -ErrorAction Stop | Out-Null
            $mgReady = $true
        }
        catch {
            if ($mgRetryCount -eq 1) {
                Write-Host ""
                Write-Host "       Graph permissions not yet active, retrying..." -ForegroundColor Yellow
            }
            if ($mgRetryCount -ge 18) { throw }
            Start-Sleep -Seconds 10
            Write-Host "." -NoNewline -ForegroundColor Cyan
        }
    }
    if ($mgRetryCount -gt 1) { Write-Host "" }

    Write-Host "  [3/6] Building connection configuration..." -ForegroundColor Cyan
    $externalConnection = Set-CCConfiguration `
        -ConnectionId $ConnectionId `
        -ConnectionName $ConnectionName `
        -ConnectionDescription $ConnectionDescription `
        -ConnectionBaseUrls $ConnectionBaseUrls `
        -Schema $Schema `
        -ResultLayoutPath $ResultLayoutPath
    $connectionId = $externalConnection.connection.id

    Write-Host "  [4/6] Creating/updating external connection '$connectionId'..." -ForegroundColor Cyan
    $existingConnection = Get-MgExternalConnection -ExternalConnectionId $connectionId -ErrorAction SilentlyContinue

    if ($existingConnection) {
        if ($existingConnection.State -ne 'deleting') {
            Write-Host "       Deleting existing connection '$connectionId' before recreation..." -ForegroundColor Cyan
            Remove-MgExternalConnection -ExternalConnectionId $connectionId -ErrorAction Stop | Out-Null
        }
        else {
            Write-Host "       Connection '$connectionId' is already being deleted..." -ForegroundColor Cyan
        }

        Write-Host "       Waiting for deletion to complete..." -ForegroundColor Cyan -NoNewline
        do {
            Start-Sleep -Seconds 10
            try {
                $existingConnection = Get-MgExternalConnection -ExternalConnectionId $connectionId -ErrorAction Stop
            }
            catch {
                $existingConnection = $null
            }
            Write-Host "." -NoNewline -ForegroundColor Cyan
        } while ($existingConnection)
        Write-Host ""
    }

    # --- Create connection ---
    $connectionCreated = $false
    $createRetryCount = 0

    $connectionBody = $externalConnection.connection | ConvertTo-Json -Depth 20 -Compress

    while (-not $connectionCreated) {
        try {
            $createRetryCount++
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/external/connections" -Body $connectionBody -ContentType "application/json" -ErrorAction Stop | Out-Null
            $connectionCreated = $true
        }
        catch {
            $createError = $_.Exception.Message

            if ($createError -match 'NameAlreadyExists|The specified resource name already exists') {
                if ($createRetryCount -eq 1) {
                    Write-Host "       Connection name is still being released by Microsoft Graph. Waiting before retrying..." -ForegroundColor Yellow
                }
                Start-Sleep -Seconds 15
                Write-Host "." -NoNewline -ForegroundColor Cyan
                continue
            }

            if ($createError -match '403|Forbidden|AccessDenied') {
                if ($createRetryCount -ge 12) { throw }
                if ($createRetryCount -eq 1) {
                    Write-Host ""
                    Write-Host "       Write permission not yet active, retrying..." -ForegroundColor Yellow
                }
                Start-Sleep -Seconds 10
                Write-Host "." -NoNewline -ForegroundColor Cyan
                continue
            }

            throw
        }
    }

    if ($createRetryCount -gt 1) {
        Write-Host ""
    }

    Write-Host "  [5/6] Creating or updating schema..." -ForegroundColor Cyan
    $schemaBody = @{
        baseType   = "microsoft.graph.externalItem"
        properties = $externalConnection.schema
    }

    $schemaSubmitted  = $false
    $schemaRetryCount = 0
    while (-not $schemaSubmitted) {
        try {
            $schemaRetryCount++
            Update-MgExternalConnectionSchema -ExternalConnectionId $connectionId -BodyParameter $schemaBody -ErrorAction Stop | Out-Null
            $schemaSubmitted = $true
        }
        catch {
            if ($schemaRetryCount -ge 12) { throw }
            if ($schemaRetryCount -eq 1) {
                Write-Host ""
                Write-Host "       Schema update not yet allowed, retrying..." -ForegroundColor Yellow
            }
            Start-Sleep -Seconds 10
            Write-Host "." -NoNewline -ForegroundColor Cyan
        }
    }
    if ($schemaRetryCount -gt 1) { Write-Host "" }

    Write-Host "       Waiting for schema provisioning..." -ForegroundColor Cyan -NoNewline
    do {
        Start-Sleep -Seconds 30
        $connection = Get-MgExternalConnection -ExternalConnectionId $connectionId
        Write-Host "." -NoNewLine -ForegroundColor Cyan
    } while ($connection.State -eq "draft")
    Write-Host "" 

    # --- Enable Copilot visibility ---
    if (-not $SkipCopilotVisibility) {
        Write-Host "  [6/6] Enabling Copilot visibility..." -ForegroundColor Cyan
        $visibilityBody = @{
            enabledContentExperiences = "search"
        } | ConvertTo-Json

        Invoke-MgGraphRequest `
            -Method PATCH `
            -Uri "https://graph.microsoft.com/beta/external/connections/$($connectionId)" `
            -Body $visibilityBody `
            -ContentType "application/json" `
            -ErrorAction Stop | Out-Null
    }

    # --- Return created connection ---
    Write-Host ""
    Write-Host "Copilot Connector connection created !" -ForegroundColor White

    Get-MgExternalConnection -ExternalConnectionId $connectionId
    }
    catch {
        Write-Error "New-CCConnection failed: $_"
        throw
    }
}
