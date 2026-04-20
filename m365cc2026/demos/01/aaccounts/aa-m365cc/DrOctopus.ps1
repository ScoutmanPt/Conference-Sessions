param(
    [string] $Runbook,
    [string] $Parms ,
    [string] $Runit ,
    [string] $List ,
    [string] $ID
)

$ErrorActionPreference = "Stop"
$Scope = "[DrOctopus]v1.1"
Write-Output "$Scope Start"

Write-Output "$Scope  Connect to Azure"
Connect-AzAccount -Identity

Write-Output "$Scope  Collect Variables"
$ResourceGroupName = Get-AutomationVariable -Name 'ResourceGroupName'
$AutomationAccountName = Get-AutomationVariable -Name 'AutomationAccountName'
$ReportCenter = Get-AutomationVariable -Name 'ReportCenter'
$SiteUrl = Get-AutomationVariable -Name 'SiteUrl'
$TeamsWebHookUrl = Get-AutomationVariable -Name 'TeamsWebHookUrl'
Write-Output "$Scope  Disconnect from Azure"


$parmsInternal = @{}
$parmsInternal.Add("ReportCenter", $ReportCenter)
$parmsInternal.Add("SiteUrl", $SiteUrl)
$parmsInternal.Add("TeamsWebHookUrl", $TeamsWebHookUrl)

Write-Output "$Scope   Variables"
Write-Output "$Scope   ##################"
Write-Output "$Scope    Runbook:$Runbook"
Write-Output "$Scope    Parms:$Parms"
Write-Output "$Scope    Runit:$Runit"
Write-Output "$Scope    List:$List"
Write-Output "$Scope    ID:$ID"
Write-Output "$Scope    ResourceGroupName:$resourceGroupName"
Write-Output "$Scope    AutomationAccountName:$automationAccountName"
Write-Output "$Scope    ReportCenter:$ReportCenter"
Write-Output "$Scope    SiteUrl:$SiteUrl"
Write-Output "$Scope    TeamsWebHookUrl $TeamsWebHookUrl"

Write-Output "$Scope    Runbook:$Runbook"
Write-Output "$Scope   ##################"
Write-Output "$Scope   Start $Runbook"
$job = Start-AzAutomationRunbook -Name $Runbook -ResourceGroupName $resourceGroupName  `
                                -AutomationAccountName $automationAccountName `
                                -Parameters $parmsInternal 
Write-Output "$Scope   End $Runbook"
Write-Output "$Scope   Disconnect Azure"
Disconnect-AzAccount 

Write-Output "$Scope  Connect to $SiteUrl "
Connect-PnPOnline -Url $SiteUrl -ManagedIdentity
Write-Output "$Scope  Token=$(Get-PnPAccessToken)"

Write-Output "$Scope   Update Item Runit=False"

$tmp=Set-PnPListItem -List $List -Identity $ID -Values @{"RunIt" = "FALSE"}
Disconnect-PnPOnline
Write-Output "$Scope  Disconnect from $SiteUrl "
Write-Output "$Scope   End"