@{
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'PDragon'
    Description       = 'PowerShell module for creating and managing Microsoft Copilot connectors.'
    PowerShellVersion = '7.2'
    RootModule        = 'PDragon.CopilotConnector.psm1'

    RequiredModules   = @(
        @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Applications'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Search'; ModuleVersion = '2.0.0' }
    )

    FunctionsToExport = @(
        'Register-CCApp'
        'Unregister-CCApp'
        'Get-CCApp'
        'New-CCConnection'
        'New-CCProperty'
        'Get-CCSchema'
        'Set-CCConfiguration'
    )

    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()
}
