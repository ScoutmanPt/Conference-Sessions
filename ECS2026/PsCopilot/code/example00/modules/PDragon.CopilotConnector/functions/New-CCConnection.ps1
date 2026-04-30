function New-CCConnection {
<#
.SYNOPSIS
    Creates or updates a Microsoft Graph external connection for a Copilot connector.

.DESCRIPTION
    Reads credentials and tenant configuration from config.ini and a SecretManagement
    vault, connects to Microsoft Graph, then creates or updates the external connection
    and its schema. Waits for schema provisioning to complete before returning.
    Optionally enables Copilot visibility (search content experience) on the connection.

    Use -Force to delete an existing connection before recreating it. If the connection
    is already in a 'deleting' state the function waits for deletion to complete.

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

.PARAMETER ConfigPath
    Full path to the config.ini file written by Register-CCApp, containing
    TenantId and ClientId.

.PARAMETER SkipCopilotVisibility
    Skips the step that enables the 'search' content experience on the connection.

.PARAMETER IconPath
    Optional path to an image file (.png, .svg, .jpg) to use as the connection icon
    in the Microsoft Search admin center. Replaces the default coloured initials tile.
    A square PNG (96x96 or 192x192 px) is recommended.

.PARAMETER Force
    Deletes an existing connection with the same ConnectionId before creating a
    new one. Waits for the deletion to complete.

.EXAMPLE
    New-CCConnection -ConnectionId 'myconn' -ConnectionName 'My Connector' `
        -ConnectionDescription 'Demo connector' `
        -ConnectionBaseUrls @('https://example.com') `
        -Schema $schema `
        -ResultLayoutPath '.\assets\resultLayout.json' `
        -SecretName 'myconnpowershell' `
        -ConfigPath '.\config.ini'

.EXAMPLE
    New-CCConnection @params -IconPath '.\assets\icon.png' -Force
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ConnectionId,
        [Parameter(Mandatory)] [string] $ConnectionName,
        [Parameter(Mandatory)] [string] $ConnectionDescription,
        [Parameter(Mandatory)] [string[]] $ConnectionBaseUrls,
        [Parameter(Mandatory)] [hashtable[]] $Schema,
        [Parameter(Mandatory)] [string] $ResultLayoutPath,
        [string] $SecretName = "secretnamepowershell",
        [string] $ConfigPath,
        [string] $IconPath,
        [switch] $SkipCopilotVisibility,
        [switch] $Force
    )

    # --- Parameter validation ---
    if (-not (Test-Path $ResultLayoutPath))           { throw "ResultLayoutPath not found at: $ResultLayoutPath" }
    if (-not (Test-Path $ConfigPath))                { throw "config.ini not found at: $ConfigPath" }
    if ($IconPath -and -not (Test-Path $IconPath))   { throw "IconPath not found at: $IconPath" }
    if ($IconPath) {
        $iconExtension = [System.IO.Path]::GetExtension($IconPath).ToLower()
        if ($iconExtension -notin @('.png', '.svg', '.jpg', '.jpeg')) {
            throw "Unsupported icon format '$iconExtension'. Use .png, .svg, or .jpg."
        }
    }

    try {
    Write-Host ""
    Write-Host "Creating new Copilot connector connection ---" -ForegroundColor White
    Write-Host ""
    Write-Host "  ConnectionId          : '$ConnectionId'" -ForegroundColor White
    Write-Host "  ConnectionName        : '$ConnectionName'" -ForegroundColor White
    Write-Host "  ConnectionDescription : '$ConnectionDescription'" -ForegroundColor White
    Write-Host "  ConnectionBaseUrls    : '$($ConnectionBaseUrls -join ', ')'" -ForegroundColor White
    Write-Host "  SecretName            : '$SecretName'" -ForegroundColor White
    Write-Host "  ConfigPath            : '$ConfigPath'" -ForegroundColor White
    Write-Host "  ResultLayoutPath      : '$ResultLayoutPath'" -ForegroundColor White
    if ($IconPath) {
    Write-Host "  IconPath              : '$IconPath'" -ForegroundColor White
    }
    Write-Host ""

    Write-Host "  [1/6] Reading config and credentials..." -ForegroundColor Cyan
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-StringData

    Write-Host ""
    $credential = Get-Secret -Name $SecretName

    if ([string]::IsNullOrWhiteSpace($config.TenantId)) {
        throw "config.ini is missing TenantId. Run Register-CCApp first."
    }

    if ([string]::IsNullOrWhiteSpace($config.ClientId)) {
        throw "config.ini is missing ClientId. Run Register-CCApp first."
    }

    if ($credential -is [securestring]) {
        $credential = [pscredential]::new($config.ClientId, $credential)
    }

    if ($credential -isnot [pscredential] -or [string]::IsNullOrWhiteSpace($credential.UserName)) {
        throw "Secret '$SecretName' must contain a PSCredential with the client ID as username and client secret as password."
    }

    Write-Host "  [2/6] Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Connect-MgGraph -ClientSecretCredential $credential -TenantId $config.TenantId -NoWelcome -ContextScope Process

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

    if ($existingConnection -and $Force) {
        if ($existingConnection.State -ne 'deleting') {
            Write-Host "       Deleting existing connection '$connectionId'(-Force paramaeter is on)..." -ForegroundColor Cyan
            Remove-MgExternalConnection -ExternalConnectionId $connectionId -ErrorAction Stop | Out-Null
        }
        else {
            Write-Host "       Connection '$connectionId' is already being deleted..." -ForegroundColor Cyan
        }

        Write-Host "       Waiting for deletion to complete..." -ForegroundColor Cyan -NoNewline
        do {
            Start-Sleep -Seconds 10
            $existingConnection = Get-MgExternalConnection -ExternalConnectionId $connectionId -ErrorAction SilentlyContinue
            Write-Host "." -NoNewline -ForegroundColor Cyan
        } while ($existingConnection)
        Write-Host ""

        $existingConnection = $null
    }

    # --- Create or update connection ---
    if ($existingConnection) {
        Update-MgExternalConnection -ExternalConnectionId $connectionId -BodyParameter $externalConnection.connection -ErrorAction Stop | Out-Null
    }
    else {
        New-MgExternalConnection -BodyParameter $externalConnection.connection -ErrorAction Stop | Out-Null
    }

    Write-Host "  [5/6] Creating or updating schema..." -ForegroundColor Cyan
    $schemaBody = @{
        baseType   = "microsoft.graph.externalItem"
        properties = $externalConnection.schema
    }

    Update-MgExternalConnectionSchema -ExternalConnectionId $connectionId -BodyParameter $schemaBody -ErrorAction Stop | Out-Null

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
            -Uri "https://graph.microsoft.com/beta/external/connections/$connectionId" `
            -Body $visibilityBody `
            -ContentType "application/json" | Out-Null
    }

    # --- Upload icon (optional) ---
    if ($IconPath) {
        Write-Host "  [+]  Uploading connection icon..." -ForegroundColor Cyan
        $iconContentType = switch ([System.IO.Path]::GetExtension($IconPath).ToLower()) {
            '.png'  { 'image/png' }
            '.svg'  { 'image/svg+xml' }
            '.jpg'  { 'image/jpeg' }
            '.jpeg' { 'image/jpeg' }
        }
        $iconBytes = [System.IO.File]::ReadAllBytes($IconPath)
        Invoke-MgGraphRequest `
            -Method PUT `
            -Uri "https://graph.microsoft.com/v1.0/external/connections/$connectionId/connectorInfo/icon" `
            -Body $iconBytes `
            -ContentType $iconContentType | Out-Null
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
