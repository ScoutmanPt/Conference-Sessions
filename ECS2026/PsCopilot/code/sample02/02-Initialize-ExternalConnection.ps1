. (Join-Path $PSScriptRoot "Initialize-GraphClient.ps1")
. (Join-Path $PSScriptRoot "ConnectionConfiguration.ps1")

Write-Host "Creating or updating external connection..." -NoNewLine
while ($existingConnection.State -eq 'draft') {
    $existingConnection = Get-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id
    Start-Sleep -Seconds 10
    Write-Host " still in draft" -NoNewLine -ForegroundColor Yellow
} 
while ( $null -ne $existingConnection){
    Remove-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id  -OnErrorAction SilentlyContinue       
    Start-Sleep -Seconds 5
    $existingConnection = Get-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id -ErrorAction SilentlyContinue
} 

if ($existingConnection) {
    #Update-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id -BodyParameter $externalConnection.connection -ErrorAction Stop | Out-Null
    
}
else {
    New-MgExternalConnection -BodyParameter $externalConnection.connection -ErrorAction Stop | Out-Null
}

Write-Host "DONE" -ForegroundColor Green

Write-Host "Creating schema..." -NoNewLine
$body = @{
    baseType = "microsoft.graph.externalItem"
    properties = $externalConnection.schema
}

Update-MgExternalConnectionSchema -ExternalConnectionId $externalConnection.connection.id -BodyParameter $body -ErrorAction Stop
Write-Host "DONE" -ForegroundColor Green

Write-Host "Waiting for the schema to get provisioned..." -ForegroundColor Yellow -NoNewline
do {
    $connection = Get-MgExternalConnection -ExternalConnectionId $externalConnection.connection.id
    Start-Sleep -Seconds 60
    Write-Host "." -NoNewLine -ForegroundColor Yellow
} while ($connection.State -eq 'draft')

Write-Host "DONE" -ForegroundColor Green

Write-Host "Set enabledContentExperiences..." -ForegroundColor Yellow -NoNewline
$body = @{
  enabledContentExperiences = @("search")
} | ConvertTo-Json

Invoke-MgGraphRequest `
  -Method PATCH `
  -Uri "https://graph.microsoft.com/beta/external/connections/$connectionId" `
  -Body $body `
  -ContentType "application/json"
Write-Host "DONE" -ForegroundColor Green
. (Join-Path $PSScriptRoot "03-Import-Content.ps1")