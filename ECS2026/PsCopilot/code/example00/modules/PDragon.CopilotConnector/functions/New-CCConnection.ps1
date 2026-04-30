function New-CCConnection {
    [CmdletBinding()]
    param(
        [string] $SecretName = "testconnpowershell",
        [string] $ConfigPath,
        [string] $ConnectionConfigurationPath = (Join-Path $PSScriptRoot "ConnectionConfiguration.ps1"),
        [switch] $SkipCopilotVisibility
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath))                     { throw "ConfigPath cannot be empty." }
    if (-not (Test-Path $ConfigPath))                                    { throw "config.ini not found at: $ConfigPath" }
    if (-not (Test-Path $ConnectionConfigurationPath))                   { throw "ConnectionConfigurationPath not found at: $ConnectionConfigurationPath" }

    try {
    $config = Get-Content -Path $ConfigPath | ConvertFrom-StringData
    $credential = Get-Secret -Name $SecretName

    if ([string]::IsNullOrWhiteSpace($config.TenantId)) {
        throw "config.ini is missing TenantId. Run New-CopilotConnectorEntraApp first."
    }

    if ([string]::IsNullOrWhiteSpace($config.ClientId)) {
        throw "config.ini is missing ClientId. Run New-CopilotConnectorEntraApp first."
    }

    if ($credential -is [securestring]) {
        $credential = [pscredential]::new($config.ClientId, $credential)
    }

    if ($credential -isnot [pscredential] -or [string]::IsNullOrWhiteSpace($credential.UserName)) {
        throw "Secret '$SecretName' must contain a PSCredential with the client ID as username and client secret as password."
    }

    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Connect-MgGraph -ClientSecretCredential $credential -TenantId $config.TenantId -NoWelcome -ContextScope Process

    . $ConnectionConfigurationPath
    $schema = Get-CCSchema -Example1
    $externalConnection = Set-CCConfiguration `
        -ConnectionId "testconn" `
        -ConnectionName "TestConn" `
        -ConnectionDescription "Example Copilot connector created with PowerShell" `
        -ConnectionBaseUrls @("https://example.com") `
        -Schema $schema
    $connectionId = $externalConnection.connection.id

    Write-Host "Creating or updating external connection '$connectionId'..." -NoNewLine
    $existingConnection = Get-MgExternalConnection -ExternalConnectionId $connectionId -ErrorAction SilentlyContinue

    if ($existingConnection) {
        Update-MgExternalConnection -ExternalConnectionId $connectionId -BodyParameter $externalConnection.connection -ErrorAction Stop | Out-Null
    }
    else {
        New-MgExternalConnection -BodyParameter $externalConnection.connection -ErrorAction Stop | Out-Null
    }

    Write-Host "DONE" -ForegroundColor Green

    Write-Host "Creating or updating schema..." -NoNewLine
    $schemaBody = @{
        baseType   = "microsoft.graph.externalItem"
        properties = $externalConnection.schema
    }

    Update-MgExternalConnectionSchema -ExternalConnectionId $connectionId -BodyParameter $schemaBody -ErrorAction Stop | Out-Null
    Write-Host "DONE" -ForegroundColor Green

    Write-Host "Waiting for schema provisioning..." -ForegroundColor Yellow -NoNewline
    do {
        Start-Sleep -Seconds 30
        $connection = Get-MgExternalConnection -ExternalConnectionId $connectionId
        Write-Host "." -NoNewLine -ForegroundColor Yellow
    } while ($connection.State -eq "draft")

    Write-Host "DONE" -ForegroundColor Green

    if (-not $SkipCopilotVisibility) {
        Write-Host "Enabling Copilot visibility..." -NoNewLine
        $visibilityBody = @{
            enabledContentExperiences = @("search")
        } | ConvertTo-Json

        Invoke-MgGraphRequest `
            -Method PATCH `
            -Uri "https://graph.microsoft.com/beta/external/connections/$connectionId" `
            -Body $visibilityBody `
            -ContentType "application/json" | Out-Null

        Write-Host "DONE" -ForegroundColor Green
    }

    Get-MgExternalConnection -ExternalConnectionId $connectionId
    }
    catch {
        Write-Error "New-CCConnection failed: $_"
        throw
    }
}
