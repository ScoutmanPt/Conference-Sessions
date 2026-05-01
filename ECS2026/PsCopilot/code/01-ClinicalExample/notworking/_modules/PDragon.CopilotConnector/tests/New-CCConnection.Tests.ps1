BeforeAll {
    . (Join-Path $PSScriptRoot '../functions/New-CCProperty.ps1')
    . (Join-Path $PSScriptRoot '../functions/Set-CCConfiguration.ps1')
    . (Join-Path $PSScriptRoot '../functions/New-CCConnection.ps1')
}

Describe 'New-CCConnection' {

    BeforeEach {
        # --- Test Drive files ---
        $script:layoutPath = Join-Path $TestDrive 'resultLayout.json'
        @{ type = 'AdaptiveCard'; version = '1.6'; body = @() } | ConvertTo-Json |
            Set-Content $script:layoutPath

        $script:schema = @(
            New-CCProperty -Name 'title' -Type 'String' -Retrievable -Labels @('title')
        )

        $script:baseParams = @{
            ConnectionId          = 'testconn'
            ConnectionName        = 'Test Connector'
            ConnectionDescription = 'A test'
            ConnectionBaseUrls    = @('https://example.com')
            Schema                = $script:schema
            ResultLayoutPath      = $script:layoutPath
            SecretName            = 'testsecret'
            TenantId              = 'tenant-id-1'
            AppId                 = 'app-id-1'
        }

        $script:credential = [pscredential]::new(
            'app-id-1',
            (ConvertTo-SecureString 'secret' -AsPlainText -Force)
        )

        Mock Get-Secret                    { $script:credential }
        Mock Disconnect-MgGraph            { }
        Mock Connect-MgGraph               { }
        Mock Get-MgExternalConnection      { $null }
        Mock Invoke-MgGraphRequest         { }
        Mock Update-MgExternalConnectionSchema { }
        Mock Write-Host                    { }
    }

    Context 'parameter validation' {
        It 'throws when ResultLayoutPath does not exist' {
            { New-CCConnection @script:baseParams -ResultLayoutPath 'C:\no\file.json' } |
                Should -Throw '*ResultLayoutPath not found*'
        }

        It 'throws when TenantId is empty' {
            { New-CCConnection @script:baseParams -TenantId '' } |
                Should -Throw '*TenantId*'
        }

        It 'throws when AppId is empty' {
            { New-CCConnection @script:baseParams -AppId '' } |
                Should -Throw '*AppId*'
        }
    }

    Context 'credential validation' {
        It 'throws when secret ClientId does not match AppId' {
            $wrongCred = [pscredential]::new(
                'wrong-app-id',
                (ConvertTo-SecureString 'secret' -AsPlainText -Force)
            )
            Mock Get-Secret { $wrongCred }
            { New-CCConnection @script:baseParams } | Should -Throw "*contains client id*"
        }

        It 'wraps a SecureString secret using AppId' {
            Mock Get-Secret { ConvertTo-SecureString 'secret' -AsPlainText -Force }
            # Should not throw - the SecureString branch wraps it with AppId.
            { New-CCConnection @script:baseParams } | Should -Not -Throw
        }
    }

    Context 'Graph connection with retry' {
        It 'retries Connect-MgGraph when it initially fails' {
            $script:attempt = 0
            Mock Connect-MgGraph {
                $script:attempt++
                if ($script:attempt -lt 2) { throw 'auth failed' }
            }
            { New-CCConnection @script:baseParams } | Should -Not -Throw
            Should -Invoke Connect-MgGraph -Times 2
        }

        It 'throws after 18 failed Connect-MgGraph attempts' {
            Mock Connect-MgGraph { throw 'auth failed' }
            { New-CCConnection @script:baseParams } | Should -Throw
        }
    }

    Context 'connection creation — no existing connection' {
        It 'posts to the external connections endpoint' {
            New-CCConnection @script:baseParams
            Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -match 'external/connections'
            }
        }

        It 'does not call Remove-MgExternalConnection' {
            New-CCConnection @script:baseParams
            Should -Not -Invoke Remove-MgExternalConnection
        }
    }

    Context 'connection creation — existing connection is deleted first' {
        BeforeEach {
            Mock Get-MgExternalConnection {
                [pscustomobject]@{ Id = 'testconn'; State = 'ready' }
            }
            Mock Remove-MgExternalConnection { }

            $script:pollCount = 0
            Mock Get-MgExternalConnection {
                $script:pollCount++
                if ($script:pollCount -le 1) {
                    [pscustomobject]@{ Id = 'testconn'; State = 'deleting' }
                }
                else { $null }
            }
        }

        It 'calls Remove-MgExternalConnection' {
            New-CCConnection @script:baseParams
            Should -Invoke Remove-MgExternalConnection -Times 1
        }
    }

    Context 'creation retry on 403' {
        It 'retries the POST when a 403 is returned' {
            $script:postAttempt = 0
            Mock Invoke-MgGraphRequest {
                $script:postAttempt++
                if ($script:postAttempt -lt 2 -and $Method -eq 'POST') {
                    throw 'Status: 403 (Forbidden)'
                }
            }
            { New-CCConnection @script:baseParams } | Should -Not -Throw
            $script:postAttempt | Should -BeGreaterThan 1
        }
    }

    Context 'schema provisioning' {
        It 'calls Update-MgExternalConnectionSchema' {
            New-CCConnection @script:baseParams
            Should -Invoke Update-MgExternalConnectionSchema -Times 1
        }

        It 'retries Update-MgExternalConnectionSchema on failure' {
            $script:schemaAttempt = 0
            Mock Update-MgExternalConnectionSchema {
                $script:schemaAttempt++
                if ($script:schemaAttempt -lt 2) { throw '403 Forbidden' }
            }
            Mock Get-MgExternalConnection { [pscustomobject]@{ State = 'ready' } }
            { New-CCConnection @script:baseParams } | Should -Not -Throw
            $script:schemaAttempt | Should -BeGreaterThan 1
        }
    }

    Context 'Copilot visibility' {
        It 'patches Copilot visibility by default' {
            Mock Get-MgExternalConnection { [pscustomobject]@{ State = 'ready' } }
            New-CCConnection @script:baseParams
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -match 'beta/external/connections'
            }
        }

        It 'skips Copilot visibility when -SkipCopilotVisibility is set' {
            Mock Get-MgExternalConnection { [pscustomobject]@{ State = 'ready' } }
            New-CCConnection @script:baseParams -SkipCopilotVisibility
            Should -Not -Invoke Invoke-MgGraphRequest -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -match 'beta/external/connections'
            }
        }
    }
}
