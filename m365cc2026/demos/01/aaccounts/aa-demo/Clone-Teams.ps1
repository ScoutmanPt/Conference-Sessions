param(
    [string] $SiteUrl,
    [string] $CloneTeam,
    [string] $NewTeamName,
    [string] $NewMailNickname = 'fg@rodrigopinto.onmicrosoft.com',
    [string] $NewTeamDescription = 'New Team',
    [string] $NewTeamVisibility = 'Public'
)

    $ErrorActionPreference = "Stop"
    $Scope = "[Clone-Team]v1.1"
    Write-Output "$Scope Start"
    
    Write-Output "$Scope  Connect to tenant"
    Connect-PnPOnline -ManagedIdentity

    Write-Output "$Scope  Get Token"
    $accesstoken = Get-PnPAccessToken
    Write-Output "$Scope  Get Selected Team"
    $existingTeam = Get-PnPMicrosoft365Group  -IncludeSiteUrl `
    | Where-object { $_.HasTeam -and (($_.id -eq $CloneTeam) -or ($_.Displayname -eq $CloneTeam)) } `
    | Select-Object Id, DisplayName, SiteUrl
    if ($existingTeam.Length -gt 1) {
        Write-Output ("$Scope    Hum... It seems you have [" + $existingTeam.Length + "] named [$Team]. Freaky!!!")
        $selectedTeam = $existingTeam[0]
        Write-Output ("$Scope    Selecting the first on the list ... id[{0}],name[{1}],url[{2}]" -f $selectedTeam.id, $selectedTeam.DisplayName, $selectedTeam.SiteUrl )
        $existingTeam = $selectedTeam
    }
    $cloneUrl = "https://graph.microsoft.com/beta/teams/$($existingTeam.Id)/clone" 
    Write-Output "$Scope  Get clone Url:$cloneUrl "

    $newTeam = '{ 
    "displayName": "'+ $NewTeamName + '",
    "description": "'+ $NewTeamDescription + '",
    "mailNickname": "'+ $NewMailNickname + '",
    "partsToClone": "apps,tabs,settings,channels,members",
    "visibility": "'+ $NewTeamVisibility + '"
    }'
    
    Write-Output ("$Scope  Clone new Team:$NewTeamName")
    Write-Output ("$Scope  Post clone url")
    ## Changed from Rest to WebRequest since Invoke-Rest doesn't return Headers
    $r = Invoke-WebRequest -Headers @{Authorization = "Bearer $accesstoken"; "Content-Type" = "application/json" } `
        -Uri $cloneUrl -Body $newTeam -Method POST 

    #Cloning is a long-running operation. After the POST clone returns, 
    #We need to GET the operation to see if it's 'running' or 'succeeded' or 'failed'. 
    #We should continue to GET until the status is not 'running'. 
    #The recommended delay between GETs is 5 seconds.   
    Write-Output ("
# Cloning is a long-running operation. After the POST clone returns, 
#  We need to GET the operation to see if it's 'running' or 'succeeded' or 'failed'. 
#  We should continue to GET until the status is not 'running'. 
#  The recommended delay between GETs is 5 seconds.
")
    Start-Sleep 5
    $getUrl = "https://graph.microsoft.com/beta" + $r.Headers.Location   
    $result = Invoke-RestMethod -Headers  `
    @{Authorization = "Bearer $accesstoken"; "Content-Type" = "application/json" } -Uri $getUrl  -Method Get

    while ( ($result.status -eq "inProgress") -or ($result.status -eq "Pending")) {
        Start-Sleep 5    

        $result = Invoke-RestMethod -Headers  `
        @{Authorization = "Bearer $accesstoken"; "Content-Type" = "application/json" } -Uri $getUrl  -Method Get 
        Write-Output ("$Scope  Cloning team ..." + $result.status)
        Write-Output ("$Scope  Current Status")
        $objs = $result | select-object @{l = "Operation"; e = { $_.operationType } }, createdDateTime, lastActionDateTime, status, attemptsCount, error 
        $info = "   " + ($objs | out-string)
        Write-Output ("$Scope  `n`r $info `n`r`n`r")
        Write-Output ("$Scope  Cloning team ..." + $result.status)
    }

    function Send-Message($fileLink, $reportCenter, $TeamsWebHookUrl) {
        $filelink="https://teams.microsoft.com/"

        $CardTitle = "CloneTeam"
        $CardSubTitle = "A Team was cloned!";
        $CardText = "Check it out! "
        $CardButtonRedirect = $filelink
        $CardButtonText = "Go to Teams"
        $ImageSize = "110px"
        $Image = "https://cdn.dribbble.com/users/136021/screenshots/4737243/clone-dribbble.gif"
        $ImageSize = "250px"

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
    
    Write-Output "$Scope  Connect to Azure"
    Connect-AzAccount -Identity
    Write-Output "$Scope  Collect Variables"
    $TeamsWebHookUrl = Get-AutomationVariable -Name 'TeamsWebHookUrl'
    Write-Output "$Scope  Disconnect from Azure"
    Disconnect-AzAccount

    Write-Output "$Scope   Send-TeamsMessage"
    Send-Message -FileLink $fileLink -ReportCenter $ReportCenter -TeamsWebHookUrl $TeamsWebHookUrl
    Write-Output "$Scope End"	
    Disconnect-PnPOnline
    Write-Output "$Scope   Disconnect-PnPOnline"
    Write-Output "$Scope End"    