
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

  # Power Automate Workflows webhook format (replaces retired Office 365 Connectors)
  $reportCard = '{ "type": "message", "attachments": [ { "contentType": "application/vnd.microsoft.card.adaptive", "content": { "$schema": "http://adaptivecards.io/schemas/adaptive-card.json", "type": "AdaptiveCard", "version": "1.5", "body": [ { "type": "ColumnSet", "columns": [ { "items": [ { "text": "' + $CardCaption + '", "size": "Large", "weight": "Bolder", "color": "Attention", "wrap": true, "type": "TextBlock" }, { "text": "' + $CardTitle + '", "size": "extraLarge", "weight": "bolder", "spacing": "none", "wrap": true, "type": "TextBlock" }, { "type": "TextBlock", "size": "small", "maxLines": 1, "text": "' + $CardSubTitle + '", "wrap": true }, { "type": "TextBlock", "size": "small", "text": "' + $CardText + ' [' + $CardText1Link + '](' + $CardText1LinkUrl + ')", "wrap": true } ], "type": "Column", "width": 2 }, { "items": [ { "type": "Image", "url": "' + $image + '", "altText": "1", "width": "' + $imageSize + '" } ], "type": "Column", "width": 1 } ] } ], "actions": [ { "type": "Action.OpenUrl", "url": "' + $CardButtonRedirect + '", "title": "' + $CardButtonText + '" } ] } } ] }' 
  $reportCard='{ "$schema": "http://adaptivecards.io/schemas/adaptive-card.json", "type": "AdaptiveCard", "version": "1.5", "body": [ { "type": "ColumnSet", "columns": [ { "items": [ { "text": "' + $CardCaption + '", "size": "Large", "weight": "Bolder", "color": "Attention", "wrap": true, "type": "TextBlock" }, { "text": "' + $CardTitle + '", "size": "extraLarge", "weight": "bolder", "spacing": "none", "wrap": true, "type": "TextBlock" }, { "type": "TextBlock", "size": "small", "maxLines": 1, "text": "' + $CardSubTitle + '", "wrap": true }, { "type": "TextBlock", "size": "small", "text": "' + $CardText + ' [' + $CardText1Link + '](' + $CardText1LinkUrl + ')", "wrap": true } ], "type": "Column", "width": 2 }, { "items": [ { "type": "Image", "url": "' + $image + '", "altText": "1", "width": "' + $imageSize + '" } ], "type": "Column", "width": 1 } ] } ], "actions": [ { "type": "Action.OpenUrl", "url": "' + $CardButtonRedirect + '", "title": "' + $CardButtonText + '" } ] }'
  <#
  Good!
  {
    "type": "AdaptiveCard",
    "$schema": "https://adaptivecards.io/schemas/adaptive-card.json",
    "version": "1.5",
    "body": [
    {
      "type": "ColumnSet",
      "columns": [
        {
          "items": [
            {
              "text": "",
              "size": "Large",
              "weight": "Bolder",
              "color": "Attention",
              "wrap": true,
              "type": "TextBlock"
            },
            {
              "text": "Reports",
              "size": "extraLarge",
              "weight": "bolder",
              "spacing": "none",
              "wrap": true,
              "type": "TextBlock"
            },
            {
              "type": "TextBlock",
              "size": "small",
              "maxLines": 1,
              "text": "A report was requested !",
              "wrap": true
            },
            {
              "type": "TextBlock",
              "size": "small",
              "text": "Check it out! [**Sites List Report**](https://rodrigopinto.sharepoint.com/sites/Excelsior/CReports/SharePoint/SharePointReport_20260420-035008.csv?d=wab39f2eb670c468cb286ff61d08820ac) []()",
              "wrap": true
            }
          ],
          "type": "Column",
          "width": 2
        },
        {
          "items": [
            {
              "type": "Image",
              "url": "",
              "altText": "1",
              "width": "110px"
            }
          ],
          "type": "Column",
          "width": 1
        }
      ]
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "url": "https://rodrigopinto.sharepoint.com/sites/Excelsior/CReports",
      "title": "Visit the Report Center"
    }
  ]
}

  
  #>
  $JSON = ($reportCard | ConvertTo-JSON |  ConvertFrom-Json -Depth 10)
  $Params = @{
    "URI"         = "https://prod-23.northeurope.logic.azure.com:443/workflows/a5040b5e9f5542cab73093e2a2eb98be/triggers/When_an_HTTP_request_is_received/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2FWhen_an_HTTP_request_is_received%2Frun&sv=1.0&sig=aVNGZj8MV15a_YDtcAV0k_O--gclL5vXGMhT7Fa4z6I" #$TeamsWebHookUrl
    "Method"      = 'POST'
    "Body"        = $JSON
    "ContentType" = 'application/json'
  }
	Write-Output "Body= $JSON"	
  Invoke-RestMethod @Params
}
if ($SendMsg -eq 1) {
  Write-Output "$Scope   Send-TeamsMessage"
  Send-Message -FileLink $fileLink -ReportCenter $ReportCenter -TeamsWebHookUrl $TeamsWebHookUrl
  Write-Output "$Scope End"	
}
	
