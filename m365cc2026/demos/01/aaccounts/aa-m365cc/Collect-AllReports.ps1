param(
  [String]$ReportCenter,
  [String]$SiteUrl,
  [String]$TeamsWebHookUrl
)
$ErrorActionPreference = "Stop"
$Scope = "[Collect-AllTeamsReport]v1.1"
Write-Output "$Scope Start"
Write-Output "$Scope  Get all Reports"
Write-Output "$Scope   Collect Teams"


$parmsInternal = @{}
$parmsInternal.Add("ReportCenter", $ReportCenter)
$parmsInternal.Add("SiteUrl", $SiteUrl)
$parmsInternal.Add("TeamsWebHookUrl", $TeamsWebHookUrl)

$Runbook = "Collect-TeamsReport"    
$job = Start-AzAutomationRunbook -Name $Runbook -ResourceGroupName $resourceGroupName `
    -AutomationAccountName $automationAccountName -Parameters $parmsInternal 

Write-Output "$Scope   Collect SharePoint"
$Runbook = "Collect-SitesReport"
$job = Start-AzAutomationRunbook -Name $Runbook -ResourceGroupName $resourceGroupName `
    -AutomationAccountName $automationAccountName -Parameters $parmsInternal 
    Write-Output "$Scope End"