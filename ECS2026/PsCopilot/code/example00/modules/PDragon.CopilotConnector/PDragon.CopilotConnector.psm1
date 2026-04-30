Set-StrictMode -Version Latest

Write-Host "PDragon.CopilotConnector loaded." -ForegroundColor Cyan
Write-Host "Steps:" -ForegroundColor Cyan
Write-Host "  1. Configure connector parameters and assets/resultLayout.json." -ForegroundColor Cyan
Write-Host "  2. Run Register-CCApp to create the Entra app and config.ini." -ForegroundColor Cyan
Write-Host "  3. Run New-CCConnection to create the external connection and schema." -ForegroundColor Cyan

Get-ChildItem -Path (Join-Path $PSScriptRoot "functions") -Filter "*.ps1" | ForEach-Object { . $_.FullName }

Export-ModuleMember -Function Register-CCApp, Unregister-CCApp, Get-CCApp, New-CCConnection, New-CCProperty, Get-CCSchema, Set-CCConfiguration
