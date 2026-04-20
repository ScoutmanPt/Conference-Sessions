# Requires: PnP.PowerShell   
# Usage: .\Get-SPoSites.ps1 -TenantInfo '{"TenantId":"<tenant-guid>","ClientId":"<client-id>","Thumbprint":"<cert-thumbprint>"}'

[double]$startTime = [DateTime]::UtcNow.Ticks



# Get TenantInfo from Automation Variable
$TenantId = Get-AutomationVariable -Name "TenantInfo"

# Connect to SharePoint Online with Managed Identity (Certificate)
$conn= Connect-PnPOnline -Url "https://$TenantId.sharepoint.com" -ManagedIdentity -ReturnConnection

# Get all site collections (excluding personal sites)
$sites = Get-PnPTenantSite -Connection $conn| Where-Object { $_.Url -notlike "*my.sharepoint.com*" }
[double]$endTime = [DateTime]::UtcNow.Ticks
[double]$durationTicks = $endTime - $startTime
[double]$durationSeconds = $durationTicks / [TimeSpan]::TicksPerSecond
[double]$durationMinutes = $durationSeconds / 60

# Output as JSON
$output = [PSCustomObject]@{
    Sites = $sites | Select-Object Url, Title, Template, Owner, Status
    DurationSeconds = [Math]::Round($durationSeconds, 2)
    DurationMinutes = [Math]::Round($durationMinutes, 2)
}
$output | ConvertTo-Json -Depth 4