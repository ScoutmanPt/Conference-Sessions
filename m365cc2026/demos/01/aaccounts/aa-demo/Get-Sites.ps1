# Requires: PnP.PowerShell   
$ErrorActionPreference = "Stop"

[double]$startTime = [DateTime]::UtcNow.Ticks

# Get TenantInfo from Automation Variable
$Tenant = Get-AutomationVariable -Name "Tenant"

# Connect to SharePoint Online with Managed Identity (Certificate)
$conn= Connect-PnPOnline -Url "https://$Tenant.sharepoint.com" -ManagedIdentity -ReturnConnection

# Get all site collections (excluding personal sites)
$sites = Get-PnPTenantSite -Connection $conn | Where-Object { $_.Url -notlike "*my.sharepoint.com*" }

[double]$endTime = [DateTime]::UtcNow.Ticks
[double]$durationSeconds = [TimeSpan]::FromTicks($endTime - $startTime).TotalSeconds

# Output as JSON
$output = $sites | Select-Object Url, Title, Template, Owner, Status

Write-Output "Retrieved $($sites.Count) sites in $([Math]::Round($durationSeconds, 2)) seconds."

$output | ConvertTo-Json -Depth 4