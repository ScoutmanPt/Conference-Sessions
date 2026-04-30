$configPath = Join-Path $PSScriptRoot "config.ini"
$config = Get-Content -Path $configPath | ConvertFrom-StringData
$credential = Get-Secret -Name "restcountriespowershell"

if ([string]::IsNullOrWhiteSpace($config.TenantId)) {
    throw "config.ini is missing TenantId. Run .\01-Initialize-EntraApp.ps1 again."
}

if ([string]::IsNullOrWhiteSpace($config.ClientId)) {
    throw "config.ini is missing ClientId. Run .\01-Initialize-EntraApp.ps1 again so the app id is written to config.ini."
}

if ($credential -is [securestring]) {
    $credential = [pscredential]::new($config.ClientId, $credential)
}

Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Connect-MgGraph -ClientSecretCredential $credential -TenantId $config.TenantId -NoWelcome -ContextScope Process
