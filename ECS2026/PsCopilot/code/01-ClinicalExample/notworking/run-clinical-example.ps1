$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot "./_modules/PDragon.CopilotConnector/PDragon.CopilotConnector.psd1") -Force

# Reuse the same base name for the connector and stored secret.
$connectorDisplayName = "Clinical Connector PowerShell 01"
$connectorName = $connectorDisplayName.ToLower().Replace(" ", "")

$secretName = "$($connectorName)powershell"
$protocolRoot = Join-Path $PSScriptRoot "docs"
$clinicalGroupId = "a1b2c3d4-0000-0000-0000-aabbccddeeff"
$protocolIconUrl = "https://cdn-icons-png.flaticon.com/512/2382/2382533.png"

# Return the local clinical protocol files that will be ingested into the
# external connection.
function Get-ClinicalProtocolFiles {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    Get-ChildItem -Path $Path -Recurse -File 
}

function Get-DocxPlainText {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)

    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq "word/document.xml" } | Select-Object -First 1

        if (-not $entry) {
            return ""
        }

        $reader = [System.IO.StreamReader]::new($entry.Open())

        try {
            $xml = [xml]$reader.ReadToEnd()
            $nsManager = [System.Xml.XmlNamespaceManager]::new($xml.NameTable)
            $nsManager.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")

            $paragraphs = $xml.SelectNodes("//w:p", $nsManager)
            $lines = foreach ($para in $paragraphs) {
                $runs = $para.SelectNodes(".//w:t", $nsManager)
                $text = ($runs | ForEach-Object { $_.InnerText }) -join ""
                if (-not [string]::IsNullOrWhiteSpace($text)) { $text.Trim() }
            }
            return ($lines -join " ").Trim()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $zip.Dispose()
    }
}

# Convert the protocol files into external items and ingest them into
# Microsoft Graph with a clinical-group ACL.
function Import-ExternalItems {
    param(
        [Parameter(Mandatory)]
        [Object[]] $Content,
        [Parameter(Mandatory)]
        [object] $ExternalConnection,
        [Parameter(Mandatory)]
        [string] $ClinicalGroupId
    )

    # $acl = @(
    #     @{
    #         type       = "group"
    #         value      = $ClinicalGroupId
    #         accessType = "grant"
    #     }
    # )
    $acl = @(
        @{
          accessType = "grant"
          type       = "everyone"
          value      = "everyone"
        }
      )
      
     $startDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"  
    $Content | ForEach-Object {
        $file = $_
        $rawText = if ($file.Extension -eq ".docx") {
            Get-DocxPlainText -Path $file.FullName
        }
        else {
            Get-Content -Path $file.FullName -Raw
        }

        if ([string]::IsNullOrWhiteSpace($rawText)) {
            return
        }

        $department = ($file.BaseName -split "_")[0].ToLower()
        $protocolCode = (($file.BaseName -split "_")[0..2] -join "-").ToUpper()
        $itemId = "protocol_" + ($file.BaseName -replace "[^a-zA-Z0-9]", "_")
    
       
        
        $title = $file.BaseName -replace "[_-]", " "

        $item = @{
            id         = $itemId
            properties = @{
                title                = $title
                protocolCode         = $protocolCode
                department           = $department
                fileType             = $file.Extension.TrimStart(".").ToLower()
                url                  = "https://intranet.northgate.nhs/protocols/$department/$($file.Name)"
                iconUrl              = $protocolIconUrl
                author               = "Clinical Governance Team"
                lastModifiedDateTime = $file.LastWriteTimeUtc.ToString("o")
                lastModifiedBy       = "Clinical Governance Team"
            }
            content    = @{
                value = if ($rawText.Length -gt 5000) { $rawText.Substring(0, 5000) } else { $rawText }
                type  = 'text'
            }
            acl        = $acl
        # activities = @(@{
        #   "@odata.type" = "#microsoft.graph.externalConnectors.externalActivity"
        #   type          = "created"
        #   startDateTime = $startDate
        #   performedBy   = @{
        #     type = "user"
        #     id   = $externalConnection.userId
        #   }
        # })
        }

        try {
            Set-MgExternalConnectionItem -ExternalConnectionId $ExternalConnection.Id -ExternalItemId $item.id -BodyParameter $item -ErrorAction Stop | Out-Null
            Write-Host "Imported $($file.Name)...($($itemId))" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to import $($file.Name)"
            Write-Error $_.Exception.Message
        }
    }
}

# Build the connector schema and create or update the external connection
# before importing the local clinical protocol content.
<#
$connectorApp = Register-CCApp `
    -ConnectorDisplayName $connectorDisplayName `
    -SecretName $secretName

if (-not $connectorApp) {
    throw "Connector app registration was not created. Re-run and confirm replacement of the existing app, or choose a different connector display name."
}
    

$schema = @(
    New-CCProperty -Name "title" -Type "String" -Queryable -Searchable -Retrievable -Labels @("title")
    New-CCProperty -Name "protocolCode" -Type "String" -Queryable -Retrievable -Refinable
    New-CCProperty -Name "department" -Type "String" -Queryable -Retrievable -Refinable
    New-CCProperty -Name "fileType" -Type "String" -Queryable -Retrievable -Refinable
    New-CCProperty -Name "url" -Type "String" -Retrievable -Labels @("url")
    New-CCProperty -Name "iconUrl" -Type "String" -Retrievable -Labels @("iconUrl")
    New-CCProperty -Name "author" -Type "String" -Queryable -Searchable -Retrievable
    New-CCProperty -Name "lastModifiedBy" -Type "String" -Queryable -Searchable -Retrievable -Labels @("lastModifiedBy")
    New-CCProperty -Name "lastModifiedDateTime" -Type "DateTime" -Queryable -Retrievable -Refinable -Labels @("lastModifiedDateTime")
)

$externalConnection = New-CCConnection `
    -ConnectionId $connectorName `
    -ConnectionName $connectorDisplayName `
    -ConnectionDescription "Example Copilot connector created with PowerShell" `
    -ConnectionBaseUrls @("https://example.com") `
    -Schema $schema `
    -ResultLayoutPath (Join-Path $PSScriptRoot "resultLayout.json") `
    -SecretName $secretName `
    -TenantId $connectorApp.TenantId.ToString() `
    -AppId $connectorApp.AppId.ToString() `


#>

# Retrieve the source data and ingest it into the connector.
$content = Get-ClinicalProtocolFiles -Path $protocolRoot
$externalConnection = Get-MgExternalConnection -ExternalConnectionId $connectorName -ErrorAction SilentlyContinue

Import-ExternalItems -Content $content -ExternalConnection $externalConnection -ClinicalGroupId $clinicalGroupId
##(Get-MgExternalConnectionItem -ExternalConnectionId clinicalconnectorpowershell01 -ExternalItemId protocol_DIAB_NUR_003_Insulin_Administration_Safety_SOP).Content.Value
# Use only work content.
## Use only work content.What anticoagulant should a hip replacement patient be on at discharge and for how long?
