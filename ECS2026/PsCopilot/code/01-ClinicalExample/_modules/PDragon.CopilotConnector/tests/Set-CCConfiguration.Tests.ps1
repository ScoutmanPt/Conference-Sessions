BeforeAll {
    . (Join-Path $PSScriptRoot '../functions/Set-CCConfiguration.ps1')

    $script:layoutPath = Join-Path $TestDrive 'resultLayout.json'
    @{
        type    = 'AdaptiveCard'
        version = '1.6'
        body    = @()
    } | ConvertTo-Json | Set-Content -Path $script:layoutPath

    $script:schema = @( @{ name = 'title'; type = 'String' } )

    $script:baseParams = @{
        ConnectionId          = 'testconn'
        ConnectionName        = 'Test Connector'
        ConnectionDescription = 'A test connector'
        ConnectionBaseUrls    = @('https://example.com')
        Schema                = $script:schema
        ResultLayoutPath      = $script:layoutPath
    }
}

Describe 'Set-CCConfiguration' {

    Context 'return structure' {
        It 'returns a hashtable with userId, connection, and schema keys' {
            $r = Set-CCConfiguration @script:baseParams
            $r                      | Should -BeOfType [hashtable]
            $r.ContainsKey('userId')     | Should -BeTrue
            $r.ContainsKey('connection') | Should -BeTrue
            $r.ContainsKey('schema')     | Should -BeTrue
        }

        It 'userId is a valid GUID when not specified' {
            $r = Set-CCConfiguration @script:baseParams
            [guid]::TryParse($r.userId, [ref][guid]::Empty) | Should -BeTrue
        }

        It 'uses the specified UserId' {
            $id = [guid]::NewGuid().ToString()
            $r  = Set-CCConfiguration @script:baseParams -UserId $id
            $r.userId | Should -Be $id
        }

        It 'passes schema through unchanged' {
            $r = Set-CCConfiguration @script:baseParams
            $r.schema | Should -Be $script:schema
        }
    }

    Context 'connection metadata' {
        It 'sets id, name, and description on connection' {
            $r = Set-CCConfiguration @script:baseParams
            $r.connection.id          | Should -Be 'testconn'
            $r.connection.name        | Should -Be 'Test Connector'
            $r.connection.description | Should -Be 'A test connector'
        }
    }

    Context 'activitySettings' {
        It 'includes a single urlToItemResolver' {
            $r = Set-CCConfiguration @script:baseParams
            $r.connection.activitySettings.urlToItemResolvers.Count | Should -Be 1
        }

        It 'resolver has the correct odata type' {
            $r = Set-CCConfiguration @script:baseParams
            $resolver = $r.connection.activitySettings.urlToItemResolvers[0]
            $resolver['@odata.type'] | Should -Be '#microsoft.graph.externalConnectors.itemIdResolver'
        }

        It 'resolver baseUrls matches ConnectionBaseUrls' {
            $r = Set-CCConfiguration @script:baseParams
            $r.connection.activitySettings.urlToItemResolvers[0].urlMatchInfo.baseUrls |
                Should -Be @('https://example.com')
        }

        It 'supports multiple base URLs' {
            $r = Set-CCConfiguration @script:baseParams -ConnectionBaseUrls @('https://a.com','https://b.com')
            $r.connection.activitySettings.urlToItemResolvers[0].urlMatchInfo.baseUrls |
                Should -Be @('https://a.com','https://b.com')
        }

        It 'resolver itemId is {slug}' {
            $r = Set-CCConfiguration @script:baseParams
            $r.connection.activitySettings.urlToItemResolvers[0].itemId | Should -Be '{slug}'
        }
    }

    Context 'searchSettings' {
        It 'includes one search result template' {
            $r = Set-CCConfiguration @script:baseParams
            $r.connection.searchSettings.searchResultTemplates.Count | Should -Be 1
        }

        It 'template id matches ConnectionId when <= 16 chars' {
            $r = Set-CCConfiguration @script:baseParams
            $r.connection.searchSettings.searchResultTemplates[0].id | Should -Be 'testconn'
        }

        It 'template id is truncated to 16 chars when ConnectionId is longer' {
            $r = Set-CCConfiguration @script:baseParams -ConnectionId 'averylongconnectionidentifier'
            $r.connection.searchSettings.searchResultTemplates[0].id.Length | Should -Be 16
        }

        It 'template priority is 1' {
            $r = Set-CCConfiguration @script:baseParams
            $r.connection.searchSettings.searchResultTemplates[0].priority | Should -Be 1
        }

        It 'template layout is the parsed adaptive card' {
            $r      = Set-CCConfiguration @script:baseParams
            $layout = $r.connection.searchSettings.searchResultTemplates[0].layout
            $layout | Should -Not -BeNullOrEmpty
            $layout.type    | Should -Be 'AdaptiveCard'
            $layout.version | Should -Be '1.6'
        }
    }

    Context 'validation' {
        It 'throws when ResultLayoutPath does not exist' {
            { Set-CCConfiguration @script:baseParams -ResultLayoutPath 'C:\nonexistent\layout.json' } |
                Should -Throw '*not found*'
        }
    }
}
