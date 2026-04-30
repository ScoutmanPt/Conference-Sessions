Import-Module (Join-Path $PSScriptRoot "modules/PDragon.CopilotConnector/PDragon.CopilotConnector.psd1") -Force

$connectorDisplayName = "Test Conn"
$connectorName = $connectorDisplayName.ToLower().Replace(" ", "")

$secretName="$(connectorName)powershell"
$config=(Join-Path $PSScriptRoot "config.ini") 

Register-CCApp `
    -ConnectorDisplayName $connectorDisplayName `
    -SecretName $secretName `
    -ConfigPath $config

# New-CCConnection `
#     -SecretName  $secretName`
#     -ConfigPath $config`
#     -ConnectionConfigurationPath (Join-Path $PSScriptRoot "ConnectionConfiguration.ps1")
