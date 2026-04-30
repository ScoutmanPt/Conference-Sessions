Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Variable -Name 'PDragonCopilotConnectorLoaded' -Scope Global -ErrorAction SilentlyContinue)) {
    $Global:PDragonCopilotConnectorLoaded = $true
    Write-Host ""
    Write-Host "PDragon.CopilotConnector loaded." -ForegroundColor Cyan
    Write-Host "Steps:" -ForegroundColor White
    Write-Host "  1. Configure connector parameters and assets/resultLayout.json." -ForegroundColor White
    Write-Host "  2. Run Register-CCApp to create the Entra app and config.ini." -ForegroundColor White
    Write-Host "  3. Run New-CCConnection to create the external connection and schema." -ForegroundColor White
    Write-Host ""
}

Get-ChildItem -Path (Join-Path $PSScriptRoot "functions") -Filter "*.ps1" | ForEach-Object { . $_.FullName }

Export-ModuleMember -Function Register-CCApp, Unregister-CCApp, Get-CCApp, New-CCConnection, New-CCProperty, Get-CCSchema, Set-CCConfiguration
