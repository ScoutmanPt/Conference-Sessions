<#
.SYNOPSIS
    Create (invite) multiple external (guest) users via Microsoft Graph invitations.

.DESCRIPTION
    Invites a batch of external users using the Graph invitations API. The script
    prefers to acquire a token via PnP.PowerShell helpers (Get-PnPAccessToken / Get-PnPGraphAccessToken)
    when available. If not, it falls back to IMDS (managed identity).

.PARAMETER Count
    Number of guest invitations to create. Default: 10

.PARAMETER Prefix
    Username prefix for generated guest emails. Default: guest

.PARAMETER Domain
    Domain to use for generated guest email addresses (e.g. contoso.com). Required.

.PARAMETER SponsorUPN
    Internal sponsor email (will receive invitation). Required.

.PARAMETER RedirectUrl
    Invitation redirect URL after acceptance. Default: https://www.microsoft.com

.PARAMETER AccessDays
    Number of days the invitation link / access is valid. Default: 90

.PARAMETER ExportCsv
    Optional path to export a CSV report of created invitations.

.PARAMETER WhatIf
    Switch to simulate actions without calling Graph.

EXAMPLE
    .\Create-ExternalGuests.ps1 -Count 10 -Domain example.com -SponsorUPN sponsor@contoso.com -ExportCsv C:\temp\guests.csv
#>

param(
    [int]$Count = 10,
    [string]$Prefix = "guest",
    [string]$Domain = "",
    [string]$SponsorUPN = "",
    [string]$InputCsv = "/home/s/code/github/Conference-Sessions/m365cc2026/demos/01/aaccounts/aa-etension/guests-sample.csv",
    [string]$RedirectUrl = "https://www.microsoft.com",
    [int]$AccessDays = 90,
    [string]$ExportCsv = "",
    [switch]$WhatIf,
    [switch]$AutoProvision
)

$ErrorActionPreference = 'Stop'
$start = Get-Date
$conn=$null
function Get-GraphToken {
    
    return Get-PnPAccessToken -Connection $conn
      
}

function Invite-Guest {
    param(
        [string]$GuestEmail,
        [string]$Sponsor,
        [string]$Redirect,
        [int]$Days,
        [string]$Token,
        [switch]$DryRun
    )

    $send = $false #-not $AutoProvision
    $body = @{ 
        invitedUserEmailAddress = $GuestEmail
        inviteRedirectUrl = $Redirect
        sendInvitationMessage = $send
        invitedUserMessageInfo = @{ messageBody = "You are invited to join our tenant. This invitation is valid for $Days days." }
    } | ConvertTo-Json -Depth 5

    if ($DryRun) {
        return @{ Email = $GuestEmail; Status = 'WhatIf' }
    }

    try {
        $hdr = @{ Authorization = "Bearer $Token"; 'Content-Type' = 'application/json' }
        $inv = Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/invitations' -Method Post -Headers $hdr -Body $body -ErrorAction Stop
        return @{ Email = $GuestEmail; Status = 'Invited'; InvitedUserId = $inv.invitedUser.id; InvitationId = $inv.id; RedeemUrl = ($inv.inviteRedeemUrl -as [string]) }
    } catch {
        return @{ Email = $GuestEmail; Status = 'Error'; Error = $_.Exception.Message }
    }
}
$conn=Connect-PnPOnline -Url "https://rodrigopinto.sharepoint.com" -ClientId "2b0dacad-2cdd-4b87-a045-2ba1e8e09dc4" -ReturnConnection
if ($InputCsv) {
    if (-not (Test-Path $InputCsv)) { throw "Input CSV not found: $InputCsv" }
    $rows = Import-Csv -Path $InputCsv
    Write-Output "Creating invitations from CSV rows: $($rows.Count)"
} else {
    if (-not $Domain -or -not $SponsorUPN) { throw 'Domain and SponsorUPN are required when InputCsv is not supplied.' }
    $rows = for ($i=1; $i -le $Count; $i++) {
        [PSCustomObject]@{ Domain = $Domain; SponsorUPN = $SponsorUPN; DisplayName = "$Prefix$i" }
    }
    Write-Output "Creating $($rows.Count) guest invitations (Domain: $Domain)"
}

$token = Get-GraphToken
if (-not $token) { throw 'Could not obtain Graph token' }

$results = @()
foreach ($r in $rows) {
    $domain = $r.Domain
    $sponsor = if ($r.SponsorUPN) { $r.SponsorUPN } else { $SponsorUPN }
    $display = $r.DisplayName
    # Determine email: use Email column if present, otherwise generate from display name
    if ($r.PSObject.Properties.Name -contains 'Email' -and $r.Email) { $email = $r.Email } else {
        $local = ($display -replace '\s+','.') -replace '[^a-zA-Z0-9\.\-_]',''
        $email = "{0}@{1}" -f $local.ToLower(), $domain
    }

    Write-Output "Inviting: $email (DisplayName: $display) Sponsor: $sponsor"
    $res = Invite-Guest -GuestEmail $email -Sponsor $sponsor -Redirect $RedirectUrl -Days $AccessDays -Token $token -DryRun:$WhatIf
    # add metadata
    $res['Domain'] = $domain
    $res['DisplayName'] = $display
    $res['SponsorUPN'] = $sponsor
    $results += (New-Object PSObject -Property $res)
}

if ($ExportCsv -and $results.Count -gt 0) {
    $dir = Split-Path -Path $ExportCsv -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Output "Exported results to: $ExportCsv"
}

$elapsed = (Get-Date) - $start
Write-Output "Done. Invitations attempted: $($results.Count). Duration: $($elapsed.TotalSeconds) seconds."
return $results
