$configPath = Join-Path (Split-Path -Parent $PSScriptRoot) "config.ini"
$config = Get-Content -Path $configPath | ConvertFrom-StringData
$secretName = "rodblogpowershell"
$credential = Get-Secret -Name $secretName

if ([string]::IsNullOrWhiteSpace($config.TenantId)) {
    throw "config.ini is missing TenantId. Run .\Initialize-EntraApp.ps1 again."
}

if ([string]::IsNullOrWhiteSpace($config.ClientId)) {
    throw "config.ini is missing ClientId. Run .\Initialize-EntraApp.ps1 again so the app id is written to config.ini."
}

if ($credential -is [securestring]) {
    $credential = [pscredential]::new($config.ClientId, $credential)
}

if ($credential -isnot [pscredential] -or [string]::IsNullOrWhiteSpace($credential.UserName)) {
    throw "Secret '$secretName' must be a PSCredential with the client id as the username, or a SecureString client secret with ClientId in config.ini. Run .\Initialize-EntraApp.ps1 again."
}

Connect-MgGraph -ClientSecretCredential $credential -TenantId $config.TenantId -NoWelcome
