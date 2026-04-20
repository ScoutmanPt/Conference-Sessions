
param(
	[String]$ReportCenter,
	[String]$SiteUrl,
	[String]$TeamsWebHookUrl
)

    $Scope = "[Update-TeamsTemplates]v1.1"
    Write-Output "$Scope Start"
    Write-Output "$Scope  Connect to $siteUrl"
    Connect-PnPOnline -Url $siteUrl -ManagedIdentity
    #TIP
    $batch = New-PnPBatch
    $teamsTemplatesList = "TeamsTemplates"
    ## Clean up Report List
    Write-Output "$Scope Clean up TeamsTemplates List"
    $items = Get-PnPListItem -List $teamsTemplatesList
    $items.foreach(
        {
            Remove-PnPListItem -List $teamsTemplatesList -Identity $_.Id -Batch $batch
        } 
    )

    ## Get All Teams
    Write-Output "$Scope Get Tenant Teams "
    ## get teams ,exclude TMT + Watcher
    $teams = Get-PnPMicrosoft365Group -IncludeSiteUrl | Where-object { $_.HasTeam -and $_.displayName -notlike "*TMT-*" -and $_.displayName -ne "Watcher" } 

    $teams.foreach(
        {
            Add-PnPListItem -List $teamsTemplatesList -Values @{"Title" = $_.DisplayName; "Description" = $_.Description; } -Batch $batch
            Write-Output "$Scope $($_.DisplayName) was added! "
        } 
    )

    Write-Output "Invoke-Batch "
    Invoke-PnPBatch -Batch $batch
    Disconnect-PnPOnline
    Write-Output "$Scope End"

    function Send-Message($fileLink, $reportCenter, $TeamsWebHookUrl) {
        $CardTitle = "Team Templates"
        $CardSubTitle = "An update was requested !";
        $CardText = "Check it out!" 
        $CardButtonRedirect = $ReportCenter
        $CardButtonText = "[**Teams Template List**]($fileLink)"
        $Image = "https://i.pinimg.com/originals/2e/97/91/2e9791964c8a348c34b9dd4cb975cabe.gif"
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
	



