[CmdletBinding()]
param(
    [switch] $Example1
)
$Example1=$true
Import-Module (Join-Path $PSScriptRoot "PDragon.CopilotConnector.psm1") -Force

if ($Example1) {
    Get-CopilotConnectionSchema -Example1
    return
}

Write-Host "Use -Example1 to create the sample schema from https://learn.microsoft.com/graph/connecting-external-content-manage-schema." -ForegroundColor Yellow
Write-Host "Example: .\New-CopilotConnector.ps1 -Example1" -ForegroundColor Yellow
