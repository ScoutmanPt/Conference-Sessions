<#
.SYNOPSIS
Deploy Bicep templates in this folder using the Azure CLI.

.DESCRIPTION
This script deploys a single Bicep template or all Bicep templates in the same folder
using `az deployment group create`. It will create the resource group if it doesn't
exist and can optionally accept a subscription ID and a parameters file.

.PARAMETER ResourceGroupName
Name of the Azure resource group to deploy into.

.PARAMETER Location
Azure region for the resource group (if creation is required).

.PARAMETER SubscriptionId
Optional subscription id or name to set before deploying.

.PARAMETER TemplatePath
Path to a single Bicep template to deploy. Defaults to `connections.bicep` next to this script.

.PARAMETER ParametersFile
Optional parameters file (JSON). If provided, it's passed to `az` as `@<file>`.

.PARAMETER All
Switch. If provided, deploys every `*.bicep` file in the same folder as this script.

.EXAMPLE
.
\deploy-biceps.ps1 -ResourceGroupName demo-rg -Location westus -All

.EXAMPLE
.
\deploy-biceps.ps1 -ResourceGroupName demo-rg -Location westus -TemplatePath .\connections.bicep -ParametersFile .\params.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$Location,

    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$false)]
    [string]$TemplatePath = (Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath 'connections.bicep'),

    [Parameter(Mandatory=$false)]
    [string]$ParametersFile,

    [switch]$All
)

function Assert-AzCli {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error "Azure CLI 'az' not found. Install from https://aka.ms/azure-cli."
        exit 2
    }
}

function Ensure-LoggedIn {
    try {
        az account show >/dev/null 2>&1
    } catch {
        Write-Host "Not logged in. Launching 'az login'..."
        az login | Out-Null
    }
}

function Ensure-Subscription {
    param($sub)
    if ($sub) {
        Write-Host "Setting subscription to $sub"
        az account set --subscription $sub
    }
}

function Ensure-ResourceGroup {
    param($rg, $loc)
    $existsText = az group exists --name $rg 2>$null
    $exists = $false
    if ($existsText) {
        try { $exists = ($existsText | ConvertFrom-Json) } catch { $exists = $existsText -eq 'true' }
    }
    if (-not $exists) {
        Write-Host "Creating resource group $rg in $loc..."
        az group create --name $rg --location $loc | Out-Null
    } else {
        Write-Host "Resource group $rg already exists."
    }
}

function Deploy-Template {
    param($rg, $template, $paramsFile)

    if (-not (Test-Path $template)) {
        Write-Error "Template not found: $template"
        return 1
    }

    $deployArgs = @('deployment','group','create','--resource-group',$rg,'--template-file',$template,'--mode','Incremental')

    if ($paramsFile) {
        if (-not (Test-Path $paramsFile)) {
            Write-Error "Parameters file not found: $paramsFile"
            return 1
        }
        $deployArgs += @('--parameters', "@$paramsFile")
    }

    Write-Host "Deploying template: $template to resource group: $rg"
    & az @deployArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Deployment failed for $template"
        return $LASTEXITCODE
    }
    Write-Host "Deployment succeeded: $template"
    return 0
}

# Main
Assert-AzCli
Ensure-LoggedIn
Ensure-Subscription -sub $SubscriptionId
Ensure-ResourceGroup -rg $ResourceGroupName -loc $Location

if ($All) {
    $folder = Split-Path -Parent $MyInvocation.MyCommand.Path
    $biceps = Get-ChildItem -Path $folder -Filter *.bicep | Sort-Object Name
    foreach ($file in $biceps) {
        $t = $file.FullName
        $res = Deploy-Template -rg $ResourceGroupName -template $t -paramsFile $ParametersFile
        if ($res -ne 0) { exit $res }
    }
} else {
    $resolved = Resolve-Path -Path $TemplatePath -ErrorAction Stop
    $res = Deploy-Template -rg $ResourceGroupName -template $resolved.Path -paramsFile $ParametersFile
    if ($res -ne 0) { exit $res }
}

Write-Host "All done."
