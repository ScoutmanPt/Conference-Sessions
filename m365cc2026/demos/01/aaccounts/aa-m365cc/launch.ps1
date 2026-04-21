param(
    [string] $Runbook,
    [string] $Parms ,
    [string] $Runit ,
    [string] $List ,
    [string] $ID
)
$ErrorActionPreference = "Stop"

Write-Output "launch start"
Connect-AzAccount -Identity
Start-AzAutomationRunbook -Name "test" -ResourceGroupName 'rg_m365cc'  `
                                -AutomationAccountName 'aa-m365cc'

Write-Output "launch end"