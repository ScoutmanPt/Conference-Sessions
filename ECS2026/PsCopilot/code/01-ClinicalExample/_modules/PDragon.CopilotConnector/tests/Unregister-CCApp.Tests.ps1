BeforeAll {
    . (Join-Path $PSScriptRoot '../functions/Unregister-CCApp.ps1')
}

Describe 'Unregister-CCApp' {

    BeforeEach {
        Mock Get-MgContext {
            [pscustomobject]@{ Scopes = @('Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All') }
        }
        Mock Connect-MgGraph              { }
        Mock Get-MgApplication            {
            @([pscustomobject]@{ DisplayName = 'MyApp'; AppId = 'app-id-1'; Id = 'obj-id-1' })
        }
        Mock Get-MgServicePrincipal       { @([pscustomobject]@{ Id = 'sp-id-1' }) }
        Mock Remove-MgServicePrincipal    { }
        Mock Remove-MgApplication         { }
        Mock Write-Host                   { }
    }

    Context 'happy path' {
        It 'removes the service principal before the app registration' {
            Unregister-CCApp -ConnectorDisplayName 'MyApp' -Confirm:$false

            Should -Invoke Remove-MgServicePrincipal -Times 1 -ParameterFilter {
                $ServicePrincipalId -eq 'sp-id-1'
            }
            Should -Invoke Remove-MgApplication -Times 1 -ParameterFilter {
                $ApplicationId -eq 'obj-id-1'
            }
        }

        It 'handles multiple service principals per app' {
            Mock Get-MgServicePrincipal {
                @(
                    [pscustomobject]@{ Id = 'sp-a' }
                    [pscustomobject]@{ Id = 'sp-b' }
                )
            }
            Unregister-CCApp -ConnectorDisplayName 'MyApp' -Confirm:$false
            Should -Invoke Remove-MgServicePrincipal -Times 2
        }

        It 'handles multiple apps with the same display name' {
            Mock Get-MgApplication {
                @(
                    [pscustomobject]@{ DisplayName = 'MyApp'; AppId = 'a1'; Id = 'obj-1' }
                    [pscustomobject]@{ DisplayName = 'MyApp'; AppId = 'a2'; Id = 'obj-2' }
                )
            }
            Mock Get-MgServicePrincipal { @() }
            Unregister-CCApp -ConnectorDisplayName 'MyApp' -Confirm:$false
            Should -Invoke Remove-MgApplication -Times 2
        }
    }

    Context 'WhatIf' {
        It 'does not delete anything when -WhatIf is used' {
            Unregister-CCApp -ConnectorDisplayName 'MyApp' -WhatIf
            Should -Not -Invoke Remove-MgServicePrincipal
            Should -Not -Invoke Remove-MgApplication
        }
    }

    Context 'when no apps are found' {
        BeforeEach {
            Mock Get-MgApplication { @() }
        }

        It 'emits a warning' {
            $warnings = Unregister-CCApp -ConnectorDisplayName 'NotExist' -Confirm:$false 3>&1
            $warnings | Where-Object { $_ -match 'No Entra app' } | Should -Not -BeNullOrEmpty
        }

        It 'does not attempt any deletion' {
            Unregister-CCApp -ConnectorDisplayName 'NotExist' -Confirm:$false
            Should -Not -Invoke Remove-MgApplication
        }
    }

    Context 'Graph connection' {
        It 'connects to Graph when context is missing required scopes' {
            Mock Get-MgContext { $null }
            Unregister-CCApp -ConnectorDisplayName 'MyApp' -Confirm:$false
            Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter {
                $Scopes -contains 'Application.ReadWrite.All' -and
                $Scopes -contains 'AppRoleAssignment.ReadWrite.All'
            }
        }

        It 'skips Connect-MgGraph when context already has required scopes' {
            Unregister-CCApp -ConnectorDisplayName 'MyApp' -Confirm:$false
            Should -Not -Invoke Connect-MgGraph
        }
    }
}
