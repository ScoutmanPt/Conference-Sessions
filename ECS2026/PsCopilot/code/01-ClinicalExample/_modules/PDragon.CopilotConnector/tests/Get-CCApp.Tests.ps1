BeforeAll {
    . (Join-Path $PSScriptRoot '../functions/Get-CCApp.ps1')
}

Describe 'Get-CCApp' {

    Context 'when the Graph context already has Application.Read.All' {
        BeforeEach {
            Mock Get-MgContext    { [pscustomobject]@{ Scopes = @('Application.Read.All') } }
            Mock Connect-MgGraph  { }
            Mock Get-MgApplication {
                @([pscustomobject]@{ DisplayName = 'MyApp'; AppId = 'app-id-1'; Id = 'obj-id-1' })
            }
        }

        It 'does not call Connect-MgGraph' {
            Get-CCApp -ConnectorDisplayName 'MyApp'
            Should -Not -Invoke Connect-MgGraph
        }

        It 'returns DisplayName, AppId, and Id' {
            $r = Get-CCApp -ConnectorDisplayName 'MyApp'
            $r.DisplayName | Should -Be 'MyApp'
            $r.AppId       | Should -Be 'app-id-1'
            $r.Id          | Should -Be 'obj-id-1'
        }
    }

    Context 'when the Graph context is missing the required scope' {
        BeforeEach {
            Mock Get-MgContext    { $null }
            Mock Connect-MgGraph  { }
            Mock Get-MgApplication { @() }
        }

        It 'calls Connect-MgGraph with Application.Read.All' {
            Get-CCApp -ConnectorDisplayName 'MyApp'
            Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter {
                $Scopes -contains 'Application.Read.All'
            }
        }
    }

    Context 'display name filtering' {
        BeforeEach {
            Mock Get-MgContext { [pscustomobject]@{ Scopes = @('Application.Read.All') } }
        }

        It 'builds a filter with the display name' {
            Mock Get-MgApplication { @() } -ParameterFilter {
                $Filter -eq "displayName eq 'MyApp'"
            }
            Get-CCApp -ConnectorDisplayName 'MyApp'
            Should -Invoke Get-MgApplication -Times 1 -ParameterFilter {
                $Filter -eq "displayName eq 'MyApp'"
            }
        }

        It 'escapes single quotes in display name' {
            Mock Get-MgApplication { @() } -ParameterFilter {
                $Filter -eq "displayName eq 'App''s Name'"
            }
            Get-CCApp -ConnectorDisplayName "App's Name"
            Should -Invoke Get-MgApplication -Times 1 -ParameterFilter {
                $Filter -eq "displayName eq 'App''s Name'"
            }
        }
    }

    Context 'when no apps are found' {
        BeforeEach {
            Mock Get-MgContext    { [pscustomobject]@{ Scopes = @('Application.Read.All') } }
            Mock Get-MgApplication { @() }
        }

        It 'emits a warning' {
            $warnings = Get-CCApp -ConnectorDisplayName 'Missing' 3>&1
            $warnings | Where-Object { $_ -match 'No Entra app' } | Should -Not -BeNullOrEmpty
        }

        It 'returns nothing' {
            $r = Get-CCApp -ConnectorDisplayName 'Missing'
            $r | Should -BeNullOrEmpty
        }
    }
}
