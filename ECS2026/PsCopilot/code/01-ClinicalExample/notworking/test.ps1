$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot "./_modules/PDragon.CopilotConnector/PDragon.CopilotConnector.psd1") -Force

# Reuse the same base name for the connector and stored secret.
$connectorDisplayName = "Clinical Connector PowerShell"
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
        [string] $ClinicalGroupId
    )

    $acl = @(
        @{
            type       = "group"
            value      = $ClinicalGroupId
            accessType = "grant"
        }
    )
    $ct=1    
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
        }

        try {
            #Set-MgExternalConnectionItem -ExternalConnectionId $ExternalConnection.Id -ExternalItemId $item.id -BodyParameter $item -ErrorAction Stop | Out-Null
            $item.content.value | Add-Content -Path "C:\work\code\github\Conference-Sessions\ECS2026\PsCopilot\code\01-ClinicalExample\notworking\test.txt"
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






# Retrieve the source data and ingest it into the connector.
$content = Get-ClinicalProtocolFiles -Path $protocolRoot
$externalConnection=""
Import-ExternalItems -Content $content  -ClinicalGroupId $clinicalGroupId

# Use only work content.