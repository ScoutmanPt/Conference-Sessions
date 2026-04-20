
param(
	[String]$ReportCenter,
	[String]$SiteUrl,
	[String]$TeamsWebHookUrl
)

$ErrorActionPreference = "Stop"
$Scope = "[Collect-TeamsReport]v1.1"
[int] $SendMsg = 1
Write-Output "$Scope Start"
Write-Output "$Scope  Get all Teams"
Write-Output "$Scope  SendMsg = $sendMsg"
$siteAdminUrl = $SiteUrl.Replace('.sharepoint', '-admin.sharepoint')

# Write-Output "$Scope  Connect to $siteAdminUrl"
Connect-PnPOnline -Url $siteAdminUrl -ManagedIdentity
	

Write-Output "$Scope  Get-PnPTeamsTeam"
$teams = Get-PnPTeamsTeam

$teamsCounter = 1
$teamsCount = $teams.Count

Write-Output "$Scope  Processing $teamsCount sites..."
$results = @()
foreach ($t in $teams) {
	
	Write-Output "$Scope  $teamsCounter/$teamsCount - Get Users from: $($t.DisplayName)"
	$allTeamsUsers = Get-PnPTeamsUser -Team $t.DisplayName
	$userInfo = @()
	foreach ($teamUser in $allTeamsUsers) {
		$userInfo += ""
		$results += [pscustomobject]@{
			Team            = $t.DisplayName
			TeamVisibility  = $t.Visibility
			UserDisplayName = $teamUser.DisplayName
			UserRole        = $teamUser.UserType
			UserName        = $teamUser.UserPrincipalName
		}
	}
	$teamsCounter++
}
Disconnect-PnPOnline

$reportName = "TeamsReport"
$reportSite = (Split-Path $ReportCenter -Parent).Replace('\', '/')
$reportDocLibPath = "$(([uri]$ReportCenter).LocalPath)/Teams"

Write-Output "$Scope  Connect to $reportSite "
Connect-PnPOnline -Url $reportSite -ManagedIdentity


$reportLocalPath = "{0}\{1}_{2}.csv" -f $env:TEMP, $reportName, (get-Date).toString("yyyyMMdd-HHmmsss")  
$results | Export-Csv -Path $reportLocalPath -NoTypeInformation
Write-Output "$Scope  $reportSite Add file"
Write-Output "$Scope   reportLocalPath:$reportLocalPath"
Write-Output "$Scope   reportDocLibPath :$reportDocLibPath"
$file = Add-PnPFile -Path $reportLocalPath -Folder $reportDocLibPath 
$fileLink = $file.LinkingUrl 
Disconnect-PnPOnline
Write-Output "$Scope   Disconnect-PnPOnline"


function Send-Message($fileLink, $reportCenter, $TeamsWebHookUrl) {
	$CardTitle = "Reports"
	$CardSubTitle = "A report was requested !";
	$CardText = "Check it out! [**Teams List Report**]($fileLink)" 
	$CardButtonRedirect = $ReportCenter
	$CardButtonText = "Visit the Report Center"
	$Image = "https://media0.giphy.com/media/v1.Y2lkPTc5MGI3NjExYTVkMTYzZDdiOTgzMmU2ODIzN2U2NTZjNTI5YTVhNmVlZTRhNjZmOCZlcD12MV9pbnRlcm5hbF9naWZzX2dpZklkJmN0PXM/gVzoxZFmhO5yWShg8K/giphy.gif"
	$ImageSize = "110px"

	$reportCard = '{ "type": "message", "attachments": [ { "content": { "$schema": "<http://adaptivecards.io/schemas/adaptive-card.json>", "type": "AdaptiveCard", "version": "1.5", "body": [ { "type": "ColumnSet", "columns": [ { "items": [ { "text": "' + $CardCaption + '", "size": "Large", "weight": "Bolder", "color": "Attention", "wrap": true, "type": "TextBlock" }, { "text": "' + $CardTitle + '", "size": "extraLarge", "weight": "bolder", "spacing": "none", "wrap": true, "type": "TextBlock" }, { "type": "TextBlock", "size": "small", "maxLines": 1, "text": "' + $CardSubTitle + '", "wrap": true }, { "type": "TextBlock", "size": "small", "text": "' + $CardText + ' [' + $CardText1Link + '](' + $CardText1LinkUrl + ')", "wrap": true } ], "type": "Column", "width": 2 }, { "items": [ { "type": "Image", "url": "' + $image + '", "altText": "1", "width": "' + $imageSize + '" } ], "type": "Column", "width": 1 } ] } ], "actions": [ { "type": "Action.OpenUrl", "url": "' + $CardButtonRedirect + '", "title": "' + $CardButtonText + '" } ] }, "contentType": "application/vnd.microsoft.card.adaptive" } ] }' 
	$JSON = ($reportCard | ConvertTo-JSON |  ConvertFrom-Json -Depth 10)
	$Params = @{
		"URI"         = $TeamsWebHookUrl
		"Method"      = 'POST'
		"Body"        = $JSON
		"ContentType" = 'application/json'
	}
		
	Invoke-RestMethod @Params
}
if ($SendMsg -eq 1) {
	Write-Output "$Scope   Send-TeamsMessage"
	Send-Message -FileLink $fileLink -ReportCenter $ReportCenter -TeamsWebHookUrl $TeamsWebHookUrl
	Write-Output "$Scope End"	
}
