$ErrorActionPreference = "Stop"
# msg prefix
$prefix="[CoPilot Connector][01-CreateEntraApp]:"
# Define the Microsoft Graph app role IDs required by the Copilot connector and other configurations.
$permExternalConnectionReadWrite = "f431331c-49a6-499f-be1c-62af19c34a9d"
$permExternalItemReadWrite = "8116ae0f-55c2-452d-9944-d18420f5b2c8"

$msGraphAppId = "00000003-0000-0000-c000-000000000000"

$connectorDisplayName ="AnotherTest4 (PowerShell)"
$connectorDescription ="Get information about whatever"

#secret name based on the sanitized displayname 
$sanitizedName =($connectorDisplayName -replace '\s','' -replace '\W','' -replace '[^\w]','' -replace '[^a-zA-Z0-9]','' ).ToLower()
$secretName = "s$($sanitizedName)"

Write-Host "$($prefix) Initialize EntraApp [$($connectorDisplayName)]" -ForegroundColor Cyan
Write-Host "$($prefix)  Preparing Microsoft Graph permission identifiers..." -ForegroundColor Cyan

# Define the delegated scopes needed to create apps and assign Graph app roles.
Write-Host "$($prefix)  Defining delegated Microsoft Graph scopes for app registration and role assignment..." -ForegroundColor Cyan
$graphScopes = @(
  "AppRoleAssignment.ReadWrite.All"
  "Application.ReadWrite.All"
)

# Reuse the current Microsoft Graph session when available; otherwise sign in.
Write-Host "$($prefix)  Checking for an existing Microsoft Graph connection..." -ForegroundColor Cyan
$context= Get-MgContext
if ( $null -eq $context  ) 
{
    Write-Host "$($prefix)  No Microsoft Graph context found. Signing in with device code flow..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes $graphScopes -NoWelcome -UseDeviceCode -ContextScope Process
    Write-Host "$($prefix)  Reading the Microsoft Graph context after sign-in..." -ForegroundColor Cyan
    $context = Get-MgContext
    

}
else {
    Write-Host "$($prefix)  Using existing Microsoft Graph context for tenant $($context.TenantId)." -ForegroundColor Green
}

 
# Build the RequiredResourceAccess payload for the new Entra app registration.
Write-Host "$($prefix)  Building the required resource access payload for Microsoft Graph app roles..." -ForegroundColor Cyan
$requiredResourceAccess = (@{
    "resourceAccess" = (
      @{
        id   = $permExternalConnectionReadWrite
        type = "Role"
      },
      @{
        id   = $permExternalItemReadWrite
      
        type = "Role"
      }
    )
    "resourceAppId"  = $msGraphAppId
  })

# Create the Entra app registration with the required Graph application roles.
Write-Host "$($prefix)  Creating Entra app registration '$connectorDisplayName'..." -ForegroundColor Cyan
$app = New-MgApplication -DisplayName $connectorDisplayName -RequiredResourceAccess $requiredResourceAccess

# Store the tenant and client identifiers for later commands in this session.
Write-Host "$($prefix)  Saving TenantId, ClientId, SecretName in the session variable `$global:mainApp..." -ForegroundColor Cyan
$global:mainApp = @{
    Id = $sanitizedName
    DisplayName = $connectorDisplayName
    Description = $connectorDescription
    TenantId = $context.TenantId
    ClientId = $app.AppId
    SecretName = $secretName
   
}
##save mainapp as a json file for later retrieval
$global:mainApp | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $PSScriptRoot "config.json") -Encoding utf8

# Look up Microsoft Graph's service principal so app role assignments can target it.
Write-Host "$($prefix)  Finding the Microsoft Graph service principal..." -ForegroundColor Cyan
$graphSpId = $(Get-MgServicePrincipal -Filter "appId eq '$($msGraphAppId)'").Id

# Create a service principal for the new app and grant the required app roles.
Write-Host "$($prefix)  Creating a service principal for '$connectorDisplayName'..." -ForegroundColor Cyan
$sp = New-MgServicePrincipal -AppId $app.appId
Write-Host "$($prefix)  Granting ExternalConnection.ReadWrite.OwnedBy to the service principal..." -ForegroundColor Cyan
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -AppRoleId $permExternalConnectionReadWrite -ResourceId $graphSpId |Out-Null
Write-Host "$($prefix)  Granting ExternalItem.ReadWrite.OwnedBy to the service principal..." -ForegroundColor Cyan
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -AppRoleId $permExternalItemReadWrite -ResourceId $graphSpId |Out-Null

# Create a client secret for app-only authentication.
Write-Host "$($prefix)  Creating a client secret for app-only authentication..." -ForegroundColor Cyan
$cred = Add-MgApplicationPassword -ApplicationId $app.id

# Display the app registration and generated credential details.
Write-Host "$($prefix)  Displaying the created app registration and generated credential details..." -ForegroundColor Cyan

# Store the app id and client secret as a SecretManagement credential.
Write-Host "$($prefix)  Converting the client secret into a PSCredential..." -ForegroundColor Cyan
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $app.appId, (ConvertTo-SecureString -String $cred.secretText -AsPlainText -Force)
Write-Host "$($prefix)  Storing the credential in SecretManagement as 'restcountriespowershell'..." -ForegroundColor Cyan
Set-Secret -Name $secretName -Secret $credential
Write-Host "$($prefix)EntraApp created" -ForegroundColor Cyan

<#
#delete the app registration and service principal if you want to clean up after testing
Write-Host "$($prefix)  Deleting the app registration  for cleanup..." -ForegroundColor Yellow
Remove-MgApplication -ApplicationId $app.Id
#>
