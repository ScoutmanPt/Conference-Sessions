$ErrorActionPreference = "Stop"

[double]$startTime = [DateTime]::UtcNow.Ticks


# Get TenantInfo from Automation Variable
$TenantId = Get-AutomationVariable -Name "TenantInfo"
# Connect to SharePoint Online with Managed Identity (Certificate)
$conn=  Connect-PnPOnline -Url "https://$TenantId.sharepoint.com" -ManagedIdentity -ReturnConnection
$token= Get-PnPAccessToken -ResourceTypeName Graph  -Connection $conn 
function Get-AllGuests {
    param([string]$Token)

    $url = "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,displayName,mail,userPrincipalName,companyName,createdDateTime,accountEnabled,signInActivity&`$top=999"
    $result = @()

    do {
            $resp=Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $Token" } -ErrorAction Stop

        if ($resp.value) { $result += $resp.value }
        $url = $resp.'@odata.nextLink'
    } while ($url)

    return $result
}

$allGuest=Get-AllGuests -Token $token
[double]$endTime = [DateTime]::UtcNow.Ticks
Write-Output "Retrieved $($allGuest.Count) guests in $([TimeSpan]::FromTicks($endTime - $startTime).TotalSeconds) seconds."
$allGuest