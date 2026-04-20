<#
.SYNOPSIS
    Runbook: Enumerate external (guest) users across the tenant via Microsoft Graph.

.DESCRIPTION
    Minimal, self-contained runbook to:
      - Acquire an access token for Microsoft Graph (prefer PnP token helpers; fallback to IMDS)
      - Enumerate all users where userType eq 'Guest' (handles Graph pagination)
      - Optionally check SharePoint site access count per guest (best-effort)
      - Optionally write a simple governance CSV/log entry per guest
      - Export results to CSV

.PARAMETER ExportPath
    File path for CSV export. Defaults to a timestamped file in the script folder.

.PARAMETER NoExport
    If specified, do not write CSV file.

.PARAMETER CheckSiteAccess
    If specified, attempt to enumerate SharePoint sites where guest has direct membership.
    This is best-effort and may be slow for large tenants.

.PARAMETER GovernanceExportPath
    Optional file path to append a lightweight governance CSV when a SharePoint governance list isn't available.

.PARAMETER ImdsEndpoint
    IMDS base URL (default: http://169.254.169.254). Kept configurable for testing.

.EXAMPLE
    .\ExternalUsers-EnumerateGuests.ps1 -ExportPath C:\temp\Guests.csv

    Enumerates guests and writes C:\temp\Guests.csv
#>

param(
    [string]$ExportPath = "",
    [switch]$NoExport,
    [switch]$CheckSiteAccess,
    [string]$GovernanceExportPath = "",
    [string]$ImdsEndpoint = "http://169.254.169.254"
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date

Write-Output "=== ExternalUsers-EnumerateGuests | Started: $startTime ==="

# --- Helpers ---------------------------------------------------------------
function Write-RunbookErrorAndExit {
    param([string]$Message)
    Write-Error $Message
    throw $Message
}

function Invoke-WithRetry {
    param(
        [scriptblock]$Action,
        [int]$Retries = 5,
        [string]$Context = "operation"
    )
    $attempt = 0
    while ($attempt -lt $Retries) {
        try { return & $Action }
        catch {
            # If response includes Retry-After header, respect it
            $wait = $null
            $resp = $null
            if ($_.Exception -and $_.Exception.Response) { $resp = $_.Exception.Response }
            elseif ($_.Exception.InnerException -and $_.Exception.InnerException.Response) { $resp = $_.Exception.InnerException.Response }
            if ($resp) {
                try { $retryHeader = $resp.Headers['Retry-After'] } catch { $retryHeader = $null }
                if ($retryHeader) {
                    [int]$parsed = 0
                    if ([int]::TryParse($retryHeader, [ref]$parsed)) { $wait = $parsed }
                }
            }
            if (-not $wait) { $wait = [math]::Pow(2, $attempt) }
            $attempt++
            Write-Warning "[$Context] Failed or throttled. Retrying in ${wait}s (attempt $attempt/$Retries)..."
            Start-Sleep -Seconds $wait
        }
    }
    Write-RunbookErrorAndExit "[$Context] Max retries ($Retries) exceeded."
}

function Get-GraphToken {
    <#
    Acquire a Microsoft Graph access token.
    Preference order:
      1. PnP.PowerShell helpers (Get-PnPGraphAccessToken, Get-PnPAccessToken)
      2. Managed Identity via IMDS
    This function throws on failure.
    #>

    # record start ticks for diagnostics
    [double]$startTime = [DateTime]::UtcNow.Ticks

    # Attempt to connect PnP using TenantInfo automation variable (runbook environment)
    try {
        $TenantId = Get-AutomationVariable -Name "TenantInfo" -ErrorAction SilentlyContinue
    } catch { $TenantId = $null }
    if ($TenantId) {
        try {
            Connect-PnPOnline -Url ("https://{0}.sharepoint.com" -f $TenantId) -ManagedIdentity -ReturnConnection -ErrorAction SilentlyContinue | Out-Null
        } catch { }
    }

    # 1) PnP helpers (requires Connect-PnPOnline has been run in the runbook environment)
    try {
        if (Get-Command -Name Get-PnPGraphAccessToken -ErrorAction SilentlyContinue) {
            $t = Get-PnPGraphAccessToken -ErrorAction Stop
            if ($t) { return $t }
        }
        if (Get-Command -Name Get-PnPAccessToken -ErrorAction SilentlyContinue) {
            $t = Get-PnPAccessToken -ErrorAction SilentlyContinue
            if ($t) { return $t }
        }
    } catch {
        Write-Warning "PnP token helper failed: $_"
    }

    # 2) IMDS (managed identity) fallback
    $uri = "{0}/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://graph.microsoft.com" -f $ImdsEndpoint.TrimEnd('/')
    $resp = Invoke-WithRetry -Action { Invoke-RestMethod -Uri $uri -Headers @{ Metadata = 'true' } -ErrorAction Stop } -Context 'IMDS-Token'
    if ($resp.access_token) { return $resp.access_token }

    Write-RunbookErrorAndExit "Unable to acquire Graph access token."
}

function Get-AllGuests {
    param([string]$Token)

    $url = "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,displayName,mail,userPrincipalName,companyName,createdDateTime,accountEnabled,signInActivity&`$top=999"
    $result = @()

    do {
        $resp = Invoke-WithRetry -Action {
            Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $Token" } -ErrorAction Stop
        } -Context 'GetGuests'

        if ($resp.value) { $result += $resp.value }
        $url = $resp.'@odata.nextLink'
    } while ($url)

    return $result
}

function Get-GuestSiteCount {
    param([string]$GuestUpn)
    # Minimal, best-effort count of sites where the guest has a user entry.
    if (-not (Get-Command -Name Get-PnPTenantSite -ErrorAction SilentlyContinue)) { return 0 }
    $count = 0
    $sites = Invoke-WithRetry -Action { Get-PnPTenantSite -IncludeOneDriveSites:$false -ErrorAction Stop } -Context 'GetSites'
    foreach ($s in $sites) {
        try {
            $c = Connect-PnPOnline -Url $s.Url -ManagedIdentity -ReturnConnection -ErrorAction Stop
            $u = Get-PnPUser -Connection $c -ErrorAction SilentlyContinue | Where-Object { $_.LoginName -like "*$GuestUpn*" }
            if ($u) { $count++ }
        } catch { }
    }
    return $count
}

function Log-GovernanceCsv {
    param([hashtable]$Values)
    if (-not $GovernanceExportPath) { $GovernanceExportPath = Join-Path $PSScriptRoot 'GuestAccessLog-Local.csv' }
    $obj = New-Object PSObject -Property $Values
    $exists = Test-Path $GovernanceExportPath
    $obj | Export-Csv -Path $GovernanceExportPath -NoTypeInformation -Append:($exists) -Encoding UTF8
}

# --- Main ------------------------------------------------------------------
$token = Get-GraphToken
Write-Output "Acquired Graph token. Enumerating guests..."
$guests = Get-AllGuests -Token $token
Write-Output "Total guests: $($guests.Count)"

if (-not $NoExport) {
    if (-not $ExportPath) { $ExportPath = Join-Path $PSScriptRoot ("GuestList-$((Get-Date).ToString('yyyyMMddHHmmss')).csv") }

    $rows = foreach ($g in $guests) {
        $upn = $g.userPrincipalName -or $g.mail
        $siteCount = 0
        if ($CheckSiteAccess) { $siteCount = Get-GuestSiteCount -GuestUpn $upn }

        $obj = [PSCustomObject]@{
            Id = $g.id
            DisplayName = $g.displayName
            Mail = $g.mail
            UserPrincipal = $upn
            CompanyName = $g.companyName
            CreatedDateTime = $g.createdDateTime
            AccountEnabled = $g.accountEnabled
            LastSignIn = ($g.signInActivity.lastSignInDateTime -as [string])
            SiteCount = $siteCount
        }

        # Governance CSV row (best-effort)
        try { Log-GovernanceCsv -Values @{ GuestEmail = $g.mail; GuestUPN = $upn; SiteCount = $siteCount; LastSignIn = ($g.signInActivity.lastSignInDateTime -as [string]) } } catch { }

        $obj
    }

    $rows | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported guest list to: $ExportPath"
}

$duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds,1)
Write-Output "=== Done — $($guests.Count) guests in ${duration}s ==="

return $guests
