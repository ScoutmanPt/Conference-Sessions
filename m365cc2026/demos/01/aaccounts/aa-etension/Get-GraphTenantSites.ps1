# Requires: PnP.PowerShell   

[CmdletBinding()]
param(
    [string]$TenantInfo,
    [string]$TenantInfoVariableName = 'TenantInfo',
    [string]$ManagedIdentityClientId,
    [int]$RequestsPerMinute = 180,
    [switch]$IncludePersonalSites,
    [switch]$RootSiteCollectionsOnly,
    [string]$OutputPath
)

Set-StrictMode -Version Latest  
$ErrorActionPreference = 'Stop' 

function Initialize-TenantCrawlerCommon {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Resolve-TenantCrawlerSettings -ErrorAction SilentlyContinue) {
        return
    }

    $commonScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'GraphTenantCrawler.Common.ps1'
    if (Test-Path -LiteralPath $commonScriptPath) {
        . $commonScriptPath
        return
    }

    . {
        Set-StrictMode -Version Latest  
        $ErrorActionPreference = 'Stop'

        function script:Resolve-TenantCrawlerSettings {
            [CmdletBinding()]
            param(
                [string]$TenantInfo,
                [string]$TenantInfoVariableName = 'TenantInfo'
            )

            $rawValue = $TenantInfo

            if ([string]::IsNullOrWhiteSpace($rawValue)) {
                $automationVariableCommand = Get-Command -Name Get-AutomationVariable -ErrorAction SilentlyContinue
                if ($null -ne $automationVariableCommand) {
                    $rawValue = Get-AutomationVariable -Name $TenantInfoVariableName
                }
            }

            if ([string]::IsNullOrWhiteSpace($rawValue) -and $env:TENANTINFO) {
                $rawValue = $env:TENANTINFO
            }

            if ([string]::IsNullOrWhiteSpace($rawValue)) {
                throw "No tenant settings were provided. Pass -TenantInfo or populate the '$TenantInfoVariableName' automation variable."
            }

            $parsed = $null
            if ($rawValue.TrimStart().StartsWith('{')) {
                $parsed = $rawValue | ConvertFrom-Json -Depth 10
            }

            $tenantName = $null
            $sharePointHostName = $null
            $adminUrl = $null

            if ($null -ne $parsed) {
                $tenantName = @(
                    $parsed.TenantName
                    $parsed.TenantShortName
                    $parsed.SharePointTenantName
                    $parsed.TenantId
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1

                $sharePointHostName = @(
                    $parsed.SharePointHostName
                    $parsed.HostName
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1

                $adminUrl = @(
                    $parsed.TenantAdminUrl
                    $parsed.AdminUrl
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
            }
            else {
                $tenantName = $rawValue.Trim()
            }

            if ([string]::IsNullOrWhiteSpace($sharePointHostName)) {
                if ($tenantName -match '\.sharepoint\.com$') {
                    $sharePointHostName = $tenantName
                    $tenantName = $tenantName -replace '\.sharepoint\.com$', ''
                }
                else {
                    $sharePointHostName = '{0}.sharepoint.com' -f $tenantName
                }
            }

            if ([string]::IsNullOrWhiteSpace($tenantName)) {
                $tenantName = ($sharePointHostName -replace '\.sharepoint\.com$', '')
            }

            if ([string]::IsNullOrWhiteSpace($adminUrl)) {
                $adminUrl = 'https://{0}-admin.sharepoint.com' -f $tenantName
            }

            [pscustomobject]@{
                RawValue            = $rawValue
                TenantName          = $tenantName
                SharePointHostName  = $sharePointHostName
                RootSiteUrl         = 'https://{0}' -f $sharePointHostName
                AdminUrl            = $adminUrl
                GraphBaseUrl        = 'https://graph.microsoft.com/v1.0'
                TenantInfoWasJson   = ($null -ne $parsed)
            }
        }

        function script:Connect-TenantCrawlerPnP {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [psobject]$Settings,
                [string]$ManagedIdentityClientId
            )

            $connectParams = @{
                Url              = $Settings.RootSiteUrl
                ManagedIdentity  = $true
                ReturnConnection = $true
            }

            if (-not [string]::IsNullOrWhiteSpace($ManagedIdentityClientId)) {
                $connectParams.UserAssignedManagedIdentityClientId = $ManagedIdentityClientId
            }

            Connect-PnPOnline @connectParams
        }

        function script:Get-GraphBearerTokenFromPnP {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                $Connection
            )

            if ($null -eq $Connection) {
                throw 'PnP connection was null. Call Connect-TenantCrawlerPnP first.'
            }

            if (($Connection.PSObject.Properties.Name -contains 'IsMock') -and $Connection.IsMock) {
                throw "The current PnP connection is a local mock connection ('$($Connection.ConnectionType)'). It cannot acquire a real Microsoft Graph bearer token. Run this script in Azure with a managed identity, or replace the local mock with a real authenticated PnP connection."
            }

            $getPnPAccessToken = Get-Command -Name Get-PnPAccessToken -ErrorAction SilentlyContinue
            if ($null -eq $getPnPAccessToken) {
                throw 'Get-PnPAccessToken is not available. Ensure PnP.PowerShell is imported.'
            }

            if ($getPnPAccessToken.Parameters.ContainsKey('Connection')) {
                return Get-PnPAccessToken -Connection $Connection
            }

            if ($getPnPAccessToken.Parameters.ContainsKey('ResourceUrl')) {
                return Get-PnPAccessToken -ResourceUrl 'https://graph.microsoft.com'
            }

            if ($getPnPAccessToken.Parameters.ContainsKey('ResourceTypeName')) {
                return Get-PnPAccessToken -ResourceTypeName MicrosoftGraph
            }

            throw 'Get-PnPAccessToken is available, but this installed version does not expose a supported parameter set for Microsoft Graph token acquisition.'
        }

        function script:ConvertFrom-Base64UrlString {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [string]$Value
            )

            $normalized = $Value.Replace('-', '+').Replace('_', '/')
            switch ($normalized.Length % 4) {
                2 { $normalized += '==' }
                3 { $normalized += '=' }
            }

            $bytes = [System.Convert]::FromBase64String($normalized)
            return [System.Text.Encoding]::UTF8.GetString($bytes)
        }

        function script:Get-JwtPayload {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [string]$Token
            )

            $segments = $Token.Split('.')
            if ($segments.Count -lt 2) {
                return $null
            }

            try {
                $payloadJson = ConvertFrom-Base64UrlString -Value $segments[1]
                return $payloadJson | ConvertFrom-Json -Depth 20
            }
            catch {
                return $null
            }
        }

        function script:Get-GraphErrorResponseBody {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                $Exception
            )

            if ($null -eq $Exception.Response) {
                return $null
            }

            try {
                $stream = $Exception.Response.GetResponseStream()
                if ($null -eq $stream) {
                    return $null
                }

                $reader = New-Object System.IO.StreamReader($stream)
                try {
                    return $reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                    $stream.Dispose()
                }
            }
            catch {
                return $null
            }
        }

        function script:New-AdaptiveTokenBucket {
            [CmdletBinding()]
            param(
                [string]$Name = 'default',
                [double]$RequestsPerMinute = 240,
                [double]$HeadroomRatio = 0.20,
                [int]$RetryBudget = 6
            )

            if ($RequestsPerMinute -le 0) {
                throw "RequestsPerMinute must be greater than zero for bucket '$Name'."
            }

            [ordered]@{
                Name              = $Name
                ConfiguredRpm     = $RequestsPerMinute
                HeadroomRatio     = $HeadroomRatio
                RetryBudget       = $RetryBudget
                Capacity          = $RequestsPerMinute
                Tokens            = $RequestsPerMinute
                RefillPerSecond   = ($RequestsPerMinute / 60.0)
                CalibrationFactor = 1.0
                LastRefillUtc     = [DateTime]::UtcNow
                ThrottleEvents    = 0
                PreemptiveSleeps  = 0
                TotalSleepSeconds = 0.0
            }
        }

        function script:Update-AdaptiveTokenBucket {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [hashtable]$Bucket
            )

            $now = [DateTime]::UtcNow
            $elapsedSeconds = ($now - $Bucket.LastRefillUtc).TotalSeconds

            if ($elapsedSeconds -gt 0) {
                $effectiveCapacity = [Math]::Max(1.0, $Bucket.Capacity * $Bucket.CalibrationFactor)
                $effectiveRefill = [Math]::Max(0.1, $Bucket.RefillPerSecond * $Bucket.CalibrationFactor)
                $Bucket.Tokens = [Math]::Min($effectiveCapacity, $Bucket.Tokens + ($elapsedSeconds * $effectiveRefill))
                $Bucket.LastRefillUtc = $now
            }
        }

        function script:Wait-AdaptiveTokenBucket {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [hashtable]$Bucket,
                [double]$TokenCost = 1.0
            )

            while ($true) {
                Update-AdaptiveTokenBucket -Bucket $Bucket

                $effectiveCapacity = [Math]::Max(1.0, $Bucket.Capacity * $Bucket.CalibrationFactor)
                $headroomFloor = $effectiveCapacity * $Bucket.HeadroomRatio

                if ($Bucket.Tokens -lt $TokenCost) {
                    $sleepSeconds = [Math]::Ceiling(($TokenCost - $Bucket.Tokens) / [Math]::Max(0.1, ($Bucket.RefillPerSecond * $Bucket.CalibrationFactor)))
                    Start-Sleep -Seconds $sleepSeconds
                    $Bucket.PreemptiveSleeps++
                    $Bucket.TotalSleepSeconds += $sleepSeconds
                    continue
                }

                if (($Bucket.Tokens - $TokenCost) -lt $headroomFloor) {
                    $sleepSeconds = [Math]::Ceiling(($headroomFloor - ($Bucket.Tokens - $TokenCost)) / [Math]::Max(0.1, ($Bucket.RefillPerSecond * $Bucket.CalibrationFactor)))
                    if ($sleepSeconds -gt 0) {
                        Start-Sleep -Seconds $sleepSeconds
                        $Bucket.PreemptiveSleeps++
                        $Bucket.TotalSleepSeconds += $sleepSeconds
                        continue
                    }
                }

                $Bucket.Tokens = [Math]::Max(0.0, ($Bucket.Tokens - $TokenCost))
                break
            }
        }

        function script:Register-AdaptiveTokenBucketThrottle {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [hashtable]$Bucket,
                [int]$RetryAfterSeconds = 15
            )

            $Bucket.ThrottleEvents++
            $Bucket.CalibrationFactor = [Math]::Max(0.25, $Bucket.CalibrationFactor * 0.85)
            $Bucket.Tokens = 0
            $Bucket.TotalSleepSeconds += $RetryAfterSeconds
            Start-Sleep -Seconds $RetryAfterSeconds
        }

        function script:Register-AdaptiveTokenBucketSuccess {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [hashtable]$Bucket
            )

            $Bucket.CalibrationFactor = [Math]::Min(1.0, $Bucket.CalibrationFactor + 0.02)
        }

        function script:Get-GraphRetryAfterSeconds {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                $Exception,
                [int]$Attempt = 1
            )

            $fallback = [Math]::Min(60, [Math]::Pow(2, $Attempt))

            if ($null -eq $Exception.Response) {
                return [int]$fallback
            }

            try {
                $retryAfterHeader = $Exception.Response.Headers['Retry-After']
                if ($retryAfterHeader) {
                    $raw = [string]($retryAfterHeader | Select-Object -First 1)
                    $seconds = 0
                    if ([int]::TryParse($raw, [ref]$seconds)) {
                        return [Math]::Max(1, $seconds)
                    }
                }
            }
            catch {
            }

            return [int]$fallback
        }

        function script:Invoke-GraphApiRequest {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [string]$Url,
                [Parameter(Mandatory = $true)]
                $Connection,
                [Parameter(Mandatory = $true)]
                [hashtable]$Bucket,
                [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
                [string]$Method = 'GET',
                [object]$Body,
                [hashtable]$Headers,
                [int]$MaxRetryCount = 6
            )

            $attempt = 0

            while ($true) {
                $attempt++
                if ($attempt -gt ($MaxRetryCount + 1)) {
                    throw "Graph request failed after $MaxRetryCount retries: $Url"
                }

                Wait-AdaptiveTokenBucket -Bucket $Bucket

                $token = Get-GraphBearerTokenFromPnP -Connection $Connection
                $requestHeaders = @{
                    Authorization = "Bearer $token"
                }

                if ($Headers) {
                    foreach ($headerKey in $Headers.Keys) {
                        $requestHeaders[$headerKey] = $Headers[$headerKey]
                    }
                }

                $invokeParams = @{
                    Uri         = $Url
                    Method      = $Method
                    Headers     = $requestHeaders
                    ContentType = 'application/json'
                }

                if ($PSBoundParameters.ContainsKey('Body')) {
                    $invokeParams.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 }
                }

                try {
                    $response = Invoke-RestMethod @invokeParams
                    Register-AdaptiveTokenBucketSuccess -Bucket $Bucket
                    return $response
                }
                catch {
                    $statusCode = $null
                    try {
                        $statusCode = [int]$_.Exception.Response.StatusCode
                    }
                    catch {
                    }

                    if ($statusCode -in 429, 503) {
                        $retryAfterSeconds = Get-GraphRetryAfterSeconds -Exception $_.Exception -Attempt $attempt
                        Register-AdaptiveTokenBucketThrottle -Bucket $Bucket -RetryAfterSeconds $retryAfterSeconds
                        continue
                    }

                    if ($statusCode -eq 403) {
                        $jwtPayload = Get-JwtPayload -Token $token
                        $graphErrorBody = Get-GraphErrorResponseBody -Exception $_.Exception
                        $graphError = $null

                        if (-not [string]::IsNullOrWhiteSpace($graphErrorBody)) {
                            try {
                                $graphError = ($graphErrorBody | ConvertFrom-Json -Depth 20).error
                            }
                            catch {
                            }
                        }

                        $roles = @()
                        if ($null -ne $jwtPayload -and $jwtPayload.PSObject.Properties.Name -contains 'roles') {
                            $roles = @($jwtPayload.roles)
                        }

                        $scopes = @()
                        if ($null -ne $jwtPayload -and $jwtPayload.PSObject.Properties.Name -contains 'scp') {
                            $scopes = @([string]$jwtPayload.scp -split ' ')
                        }

                        $requestId = $null
                        if ($null -ne $graphError -and $graphError.PSObject.Properties.Name -contains 'innerError') {
                            $requestId = $graphError.innerError.'request-id'
                        }

                        $requiredPermission = if ($Url -like '*/sites/getAllSites*' -or $Url -like '*/sites?*' -or $Url -match '/sites$') {
                            'Sites.Read.All application permission'
                        }
                        else {
                            'the required Microsoft Graph application permission'
                        }

                        $roleSummary = if ($roles.Count -gt 0) { ($roles -join ', ') } else { '<none>' }
                        $scopeSummary = if ($scopes.Count -gt 0) { ($scopes -join ', ') } else { '<none>' }
                        $message = if ($null -ne $graphError -and -not [string]::IsNullOrWhiteSpace([string]$graphError.message)) {
                            [string]$graphError.message
                        }
                        else {
                            'Access denied.'
                        }

                        throw "Graph returned 403 accessDenied for '$Url'. $message The token appears to have roles: $roleSummary; scopes: $scopeSummary. Tenant-wide site enumeration requires $requiredPermission granted to the managed identity app and admin-consented in Microsoft Entra ID. Request ID: $requestId"
                    }

                    throw
                }
            }
        }

        function script:Invoke-GraphPagedCollection {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [string]$InitialUrl,
                [Parameter(Mandatory = $true)]
                $Connection,
                [Parameter(Mandatory = $true)]
                [hashtable]$Bucket
            )

            $items = New-Object System.Collections.Generic.List[object]
            $nextUrl = $InitialUrl

            while (-not [string]::IsNullOrWhiteSpace($nextUrl)) {
                $page = Invoke-GraphApiRequest -Url $nextUrl -Connection $Connection -Bucket $Bucket
                $valueProperty = $page.PSObject.Properties['value']
                if ($null -ne $valueProperty -and $null -ne $valueProperty.Value) {
                    foreach ($item in $valueProperty.Value) {
                        $items.Add($item)
                    }
                }

                $nextLinkProperty = $page.PSObject.Properties['@odata.nextLink']
                $nextUrl = if ($null -ne $nextLinkProperty -and -not [string]::IsNullOrWhiteSpace([string]$nextLinkProperty.Value)) {
                    [string]$nextLinkProperty.Value
                }
                else {
                    $null
                }
            }

            return $items
        }

        function script:Get-GraphTenantSitesInternal {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [psobject]$Settings,
                [Parameter(Mandatory = $true)]
                $Connection,
                [Parameter(Mandatory = $true)]
                [hashtable]$Bucket,
                [switch]$IncludePersonalSites,
                [switch]$RootSiteCollectionsOnly
            )

            if ($RootSiteCollectionsOnly) {
                $initialUrl = '{0}/sites?$select=id,name,displayName,webUrl,siteCollection,isPersonalSite,root&$filter=siteCollection/root ne null&$top=999' -f $Settings.GraphBaseUrl
            }
            else {
                $initialUrl = '{0}/sites?search=*&$top=999' -f $Settings.GraphBaseUrl
            }

            $sites = Invoke-GraphPagedCollection -InitialUrl $initialUrl -Connection $Connection -Bucket $Bucket

            foreach ($site in $sites) {
                $webUrl = $null
                $webUrlProperty = $site.PSObject.Properties['webUrl']
                if ($null -ne $webUrlProperty -and -not [string]::IsNullOrWhiteSpace([string]$webUrlProperty.Value)) {
                    $webUrl = [string]$webUrlProperty.Value
                }

                $isPersonalSite = $false
                $isPersonalSiteProperty = $site.PSObject.Properties['isPersonalSite']
                if ($null -ne $isPersonalSiteProperty -and $null -ne $isPersonalSiteProperty.Value) {
                    $isPersonalSite = [bool]$isPersonalSiteProperty.Value
                }

                if (-not $IncludePersonalSites -and ($isPersonalSite -or $webUrl -like '*-my.sharepoint.com*')) {
                    continue
                }

                $siteCollection = $null
                $siteCollectionProperty = $site.PSObject.Properties['siteCollection']
                if ($null -ne $siteCollectionProperty) {
                    $siteCollection = $siteCollectionProperty.Value
                }

                $hostName = $null
                $dataLocationCode = $null
                if ($null -ne $siteCollection) {
                    $hostNameProperty = $siteCollection.PSObject.Properties['hostname']
                    if ($null -eq $hostNameProperty) {
                        $hostNameProperty = $siteCollection.PSObject.Properties['hostName']
                    }

                    if ($null -ne $hostNameProperty -and -not [string]::IsNullOrWhiteSpace([string]$hostNameProperty.Value)) {
                        $hostName = [string]$hostNameProperty.Value
                    }

                    $dataLocationCodeProperty = $siteCollection.PSObject.Properties['dataLocationCode']
                    if ($null -ne $dataLocationCodeProperty -and -not [string]::IsNullOrWhiteSpace([string]$dataLocationCodeProperty.Value)) {
                        $dataLocationCode = [string]$dataLocationCodeProperty.Value
                    }
                }

                if ([string]::IsNullOrWhiteSpace($hostName) -and -not [string]::IsNullOrWhiteSpace($webUrl)) {
                    try {
                        $hostName = ([Uri]$webUrl).Host
                    }
                    catch {
                    }
                }

                $isRootSite = $false
                $rootProperty = $site.PSObject.Properties['root']
                if ($null -ne $rootProperty -and $null -ne $rootProperty.Value) {
                    $isRootSite = $true
                }

                [pscustomobject]@{
                    Id               = $site.id
                    Name             = $site.name
                    DisplayName      = $site.displayName
                    WebUrl           = $webUrl
                    IsPersonalSite   = $isPersonalSite
                    HostName         = $hostName
                    DataLocationCode = $dataLocationCode
                    IsRootSite       = $isRootSite
                }
            }
        }

        function script:Write-TenantCrawlerOutput {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [object]$Data,
                [string]$OutputPath
            )

            $json = $Data | ConvertTo-Json -Depth 20

            if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
                $directory = Split-Path -Path $OutputPath -Parent
                if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                }

                $json | Set-Content -Path $OutputPath -Encoding UTF8
            }

            $json
        }
    }
}

Initialize-TenantCrawlerCommon

$startedUtc = [DateTime]::UtcNow
$settings = Resolve-TenantCrawlerSettings -TenantInfo $TenantInfo -TenantInfoVariableName $TenantInfoVariableName
$connection = Connect-TenantCrawlerPnP -Settings $settings -ManagedIdentityClientId $ManagedIdentityClientId
$bucket = New-AdaptiveTokenBucket -Name 'site-discovery' -RequestsPerMinute $RequestsPerMinute

$sites = @(Get-GraphTenantSitesInternal -Settings $settings -Connection $connection -Bucket $bucket -IncludePersonalSites:$IncludePersonalSites -RootSiteCollectionsOnly:$RootSiteCollectionsOnly)
$endedUtc = [DateTime]::UtcNow

$result = [pscustomobject]@{
    TenantName       = $settings.TenantName
    RootSiteUrl      = $settings.RootSiteUrl
    SiteCount        = $sites.Count
    StartedUtc       = $startedUtc
    EndedUtc         = $endedUtc
    DurationSeconds  = [Math]::Round(($endedUtc - $startedUtc).TotalSeconds, 2)
    Bucket           = [pscustomobject]$bucket
    Sites            = $sites
}

Write-TenantCrawlerOutput -Data $result -OutputPath $OutputPath