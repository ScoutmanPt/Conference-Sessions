Import-Module (Join-Path $PSScriptRoot "modules/PDragon.CopilotConnector/PDragon.CopilotConnector.psd1") -Force

$connectorDisplayName = "Test Conn12"
$connectorName = $connectorDisplayName.ToLower().Replace(" ", "")

$secretName="$($connectorName)powershell"
$config=(Join-Path $PSScriptRoot "config.ini") 

# Register-CCApp `
#     -ConnectorDisplayName $connectorDisplayName `
#     -SecretName $secretName `
#     -ConfigPath $config

$schema =     @(
        New-CCProperty -Name "name" -Type "String" -Queryable -Searchable -Retrievable -Labels @("title")
        New-CCProperty -Name "region" -Type "String" -Queryable -Searchable -Retrievable
        New-CCProperty -Name "subregion" -Type "String" -Queryable -Searchable -Retrievable
        New-CCProperty -Name "capital" -Type "String" -Queryable -Searchable -Retrievable
        New-CCProperty -Name "population" -Type "Int64" -Retrievable
        New-CCProperty -Name "latitude" -Type "Double" -Retrievable
        New-CCProperty -Name "longitude" -Type "Double" -Retrievable
        New-CCProperty -Name "areaInSqKm" -Type "Int64" -Retrievable
        New-CCProperty -Name "timezone" -Type "String" -Retrievable
        New-CCProperty -Name "mapUrl" -Type "String" -Retrievable -Labels @("url")
        New-CCProperty -Name "flagUrl" -Type "String" -Retrievable
        New-CCProperty -Name "borders" -Type "String" -Retrievable
        New-CCProperty -Name "languages" -Type "String" -Retrievable
        New-CCProperty -Name "currencies" -Type "String" -Retrievable
        New-CCProperty -Name "lastModifiedBy" -Type "String" -Queryable -Searchable -Retrievable -Labels @("lastModifiedBy")
        New-CCProperty -Name "lastModifiedDateTime" -Type "DateTime" -Queryable -Retrievable -Refinable -Labels @("lastModifiedDateTime")
    )
New-CCConnection `
    -ConnectionId $connectorName `
    -ConnectionName $connectorDisplayName `
    -ConnectionDescription "Example Copilot connector created with PowerShell" `
    -ConnectionBaseUrls @("https://example.com") `
    -Schema $schema `
    -ResultLayoutPath (Join-Path $PSScriptRoot "resultLayout.json") `
    -SecretName $secretName `
    -ConfigPath $config `
    -Force
