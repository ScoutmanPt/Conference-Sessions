
param(
  [String]$ReportCenter,
  [String]$SiteUrl,
  [String]$TeamsWebHookUrl
)

$ErrorActionPreference = "Stop"
$Scope = "[Collect-SharePointReport]v1.1"
[int] $SendMsg = 1
Write-Output "$Scope Start"
Write-Output "$Scope  Get all SharePoint sites"
Write-Output "$Scope  SendMsg = $sendMsg"
$siteAdminUrl = $SiteUrl.Split(".sharepoint")[0] + "-admin.sharepoint.com" 
  

Write-Output "$Scope  Connect to $siteAdminUrl"
Connect-PnPOnline -Url $siteAdminUrl -ManagedIdentity
    
Write-Output "$Scope  Get-PnPTenantSite"
$sites = Get-PnPTenantSite
$results = [System.Collections.ArrayList]::new()
$siteCounter = 1

$siteCount = $sites.Count

Write-Output "$Scope  Processing $siteCount sites..."

foreach ($site in $sites) {

  Write-Output "$Scope  $siteCounter/$siteCount - Get info from: $($site.Url)"
  $obj = [PSCustomObject]::new()
  $obj | Add-Member -MemberType NoteProperty -Name "Site" -Value $site.Title;
  $obj | Add-Member -MemberType NoteProperty -Name "SiteUrl" -Value $site.Url;
  $obj | Add-Member -MemberType NoteProperty -Name "SiteTemplate" -Value $site.Template;
  $obj | Add-Member -MemberType NoteProperty -Name "Status" -Value $site.Status;
  $obj | Add-Member -MemberType NoteProperty -Name "StorageQuota" -Value $site.StorageQuota;
  $obj | Add-Member -MemberType NoteProperty -Name "StorageQuotaWarningLevel" -Value $site.StorageQuotaWarningLevel;
  $obj | Add-Member -MemberType NoteProperty -Name "StorageUsageCurrent" -Value $site.StorageUsageCurrent;
  $results.Add($obj) | Out-Null
  $siteCounter++
}

Disconnect-PnPOnline

$reportName = "SharePointReport"
$reportSite = (Split-Path $reportCenter -Parent).Replace('\', '/')
$reportDocLibPath = "$(([uri]$reportCenter).LocalPath)/SharePoint"

Write-Output "$Scope  Connect to $reportSite "
Connect-PnPOnline -Url $reportSite -ManagedIdentity
$reportLocalPath = "{0}\{1}_{2}.csv" -f $env:TEMP, $reportName, (get-Date).toString("yyyyMMdd-HHmmsss") 
$results | Export-Csv -Path $reportLocalPath -NoTypeInformation

Write-Output "$Scope  $reportSite Add file"
Write-Output "$Scope   reportLocalPath:$reportLocalPath"
Write-Output "$Scope   reportDocLibPath :$reportDocLibPath"

$file = Add-PnPFile -Path $reportLocalPath -Folder $reportDocLibPath 

$fileLink = $file.LinkingUrl 
$fileLink = $file.LinkingUrl 
Disconnect-PnPOnline
Write-Output "$Scope   Disconnect-PnPOnline"
function Send-Message($fileLink, $reportCenter, $TeamsWebHookUrl) {
  $CardTitle = "Reports"
  $CardSubTitle = "A report was requested !";
  $CardText = "Check it out! [**Sites List Report**]($fileLink)" 
  $CardButtonRedirect = $ReportCenter
  $CardButtonText = "Visit the Report Center"
  $ImageSize = "110px"


 $reportCard='{ "$schema": "http://adaptivecards.io/schemas/adaptive-card.json", "type": "AdaptiveCard", "version": "1.5", "body": [ { "type": "ColumnSet", "columns": [ { "items": [ { "text": "' + $CardTitle + '", "size": "extraLarge", "weight": "bolder", "spacing": "none", "wrap": true, "type": "TextBlock" }, { "type": "TextBlock", "size": "small", "maxLines": 1, "text": "' + $CardSubTitle + '", "wrap": true }, { "type": "TextBlock", "size": "small", "text": "' + $CardText + '", "wrap": true } ], "type": "Column", "width": 2 } ] } ], "actions": [ { "type": "Action.OpenUrl", "url": "' + $CardButtonRedirect + '", "title": "' + $CardButtonText + '" } ] }'
  $JSON = ($reportCard | ConvertTo-JSON |  ConvertFrom-Json -Depth 10)
  $Params = @{
    "URI"         = $TeamsWebHookUrl
    "Method"      = 'POST'
    "Body"        = $JSON
    "ContentType" = 'application/json'
  }
	#for debug purposes
  #Write-Output "Body= $JSON"	
  Invoke-RestMethod @Params
}
if ($SendMsg -eq 1) {
  Write-Output "$Scope   Send-TeamsMessage"
  Send-Message -FileLink $fileLink -ReportCenter $ReportCenter -TeamsWebHookUrl $TeamsWebHookUrl
  Write-Output "$Scope End"	
}
	
