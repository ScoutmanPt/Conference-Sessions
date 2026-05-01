BeforeAll {
    . (Join-Path $PSScriptRoot '../functions/Register-CCApp.ps1')
}

Describe 'Register-CCApp' {

    BeforeEach {
        $script:configPath = Join-Path $TestDrive 'config.ini'

        Mock Get-MgContext {
            [pscustomobject]@{
                TenantId = 'tenant-id-1'
                Scopes   = @('AppRoleAssignment.ReadWrite.All','Application.ReadWrite.All','Application.Read.All')
            }
        }
        Mock Connect-MgGraph              { }
        Mock Disconnect-MgGraph           { }
        Mock Get-MgApplication            { @() }
        Mock New-MgApplication            {
            [pscustomobject]@{ AppId = 'new-app-id'; Id = 'new-obj-id'; DisplayName = 'Test Connector' }
        }
        Mock Get-MgServicePrincipal       {
            [pscustomobject]@{ Id = 'graph-sp-id' }
        }
        Mock New-MgServicePrincipal       {
            [pscustomobject]@{ Id = 'connector-sp-id' }
        }
        Mock New-MgServicePrincipalAppRoleAssignment { }
        Mock Add-MgApplicationPassword    {
            [pscustomobject]@{ SecretText = 'super-secret' }
        }
        Mock Set-Secret                   { }
        Mock Get-Secret                   {
            [pscredential]::new('new-app-id', (ConvertTo-SecureString 'super-secret' -AsPlainText -Force))
        }
        Mock Write-Host                   { }
    }

    Context 'parameter validation' {
        It 'throws when ConnectorDisplayName is empty' {
            { Register-CCApp -ConnectorDisplayName '' -ConfigPath $script:configPath } |
                Should -Throw '*ConnectorDisplayName*'
        }

        It 'throws when ConfigPath is empty' {
            { Register-CCApp -ConnectorDisplayName 'Test' -ConfigPath '' } |
                Should -Throw '*ConfigPath*'
        }

        It 'throws when ConfigPath parent directory does not exist' {
            { Register-CCApp -ConnectorDisplayName 'Test' -ConfigPath 'C:\nonexistent\dir\config.ini' } |
                Should -Throw '*parent directory*'
        }
    }

    Context 'happy path — no existing app' {
        It 'creates an app registration' {
            Register-CCApp -ConnectorDisplayName 'Test Connector' -ConfigPath $script:configPath
            Should -Invoke New-MgApplication -Times 1
        }

        It 'creates a service principal' {
            Register-CCApp -ConnectorDisplayName 'Test Connector' -ConfigPath $script:configPath
            Should -Invoke New-MgServicePrincipal -Times 1
        }

        It 'assigns two app roles' {
            Register-CCApp -ConnectorDisplayName 'Test Connector' -ConfigPath $script:configPath
            Should -Invoke New-MgServicePrincipalAppRoleAssignment -Times 2
        }

        It 'stores the credential in SecretManagement' {
            Register-CCApp -ConnectorDisplayName 'Test Connector' -ConfigPath $script:configPath
            Should -Invoke Set-Secret -Times 1
        }

        It 'writes TenantId and ClientId to config.ini' {
            Register-CCApp -ConnectorDisplayName 'Test Connector' -ConfigPath $script:configPath
            $config = Get-Content $script:configPath -Raw | ConvertFrom-StringData
            $config.TenantId | Should -Be 'tenant-id-1'
            $config.ClientId | Should -Be 'new-app-id'
        }

        It 'returns an object with AppId, ObjectId, DisplayName, SecretName, ConfigPath' {
            $r = Register-CCApp -ConnectorDisplayName 'Test Connector' -ConfigPath $script:configPath
            $r.AppId       | Should -Be 'new-app-id'
            $r.ObjectId    | Should -Be 'new-obj-id'
            $r.DisplayName | Should -Be 'Test Connector'
            $r.ConfigPath  | Should -Be $script:configPath
        }
    }

    Context 'existing app — user confirms deletion' {
        BeforeEach {
            Mock Get-MgApplication {
                @([pscustomobject]@{ DisplayName = 'Test'; AppId = 'old-app-id'; Id = 'old-obj-id' })
            }
            Mock Get-MgServicePrincipal       { @([pscustomobject]@{ Id = 'old-sp-id' }) }
            Mock Remove-MgServicePrincipal    { }
            Mock Remove-MgApplication         { }
            Mock Read-Host                    { 'DELETE' }
        }

        It 'removes old service principal and app then creates a new one' {
            Register-CCApp -ConnectorDisplayName 'Test Connector' -ConfigPath $script:configPath
            Should -Invoke Remove-MgServicePrincipal -Times 1 -ParameterFilter { $ServicePrincipalId -eq 'old-sp-id' }
            Should -Invoke Remove-MgApplication      -Times 1 -ParameterFilter { $ApplicationId -eq 'old-obj-id' }
            Should -Invoke New-MgApplication         -Times 1
        }
    }

    Context 'existing app — user cancels' {
        BeforeEach {
            Mock Get-MgApplication {
                @([pscustomobject]@{ DisplayName = 'Test'; AppId = 'old-app-id'; Id = 'old-obj-id' })
            }
            Mock Read-Host { '' }
        }

        It 'makes no changes and returns nothing' {
            $r = Register-CCApp -ConnectorDisplayName 'Test Connector' -ConfigPath $script:configPath
            Should -Not -Invoke New-MgApplication
            $r | Should -BeNullOrEmpty
        }
    }
}
