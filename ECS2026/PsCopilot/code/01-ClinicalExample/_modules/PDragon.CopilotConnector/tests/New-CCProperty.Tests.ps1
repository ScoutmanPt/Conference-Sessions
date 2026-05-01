BeforeAll {
    . (Join-Path $PSScriptRoot '../functions/New-CCProperty.ps1')
}

Describe 'New-CCProperty' {

    Context 'return type and base fields' {
        It 'returns a hashtable' {
            $r = New-CCProperty -Name 'title' -Type 'String'
            $r | Should -BeOfType [hashtable]
        }

        It 'sets name and type' {
            $r = New-CCProperty -Name 'myProp' -Type 'Int64'
            $r.name | Should -Be 'myProp'
            $r.type | Should -Be 'Int64'
        }

        It 'all boolean fields default to false' {
            $r = New-CCProperty -Name 'p' -Type 'String'
            $r.isSearchable  | Should -BeFalse
            $r.isQueryable   | Should -BeFalse
            $r.isRetrievable | Should -BeFalse
            $r.isRefinable   | Should -BeFalse
        }

        It 'sets isSearchable when -Searchable is passed' {
            $r = New-CCProperty -Name 'p' -Type 'String' -Searchable
            $r.isSearchable | Should -BeTrue
        }

        It 'sets isQueryable when -Queryable is passed' {
            $r = New-CCProperty -Name 'p' -Type 'String' -Queryable
            $r.isQueryable | Should -BeTrue
        }

        It 'sets isRetrievable when -Retrievable is passed' {
            $r = New-CCProperty -Name 'p' -Type 'String' -Retrievable
            $r.isRetrievable | Should -BeTrue
        }

        It 'sets isRefinable when -Refinable is passed' {
            $r = New-CCProperty -Name 'p' -Type 'String' -Refinable
            $r.isRefinable | Should -BeTrue
        }
    }

    Context 'validation' {
        It 'throws when both -Searchable and -Refinable are set' {
            { New-CCProperty -Name 'p' -Type 'String' -Searchable -Refinable } |
                Should -Throw '*cannot be both*'
        }

        It 'throws when -Labels are set without -Retrievable' {
            { New-CCProperty -Name 'p' -Type 'String' -Labels @('title') } |
                Should -Throw '*must be retrievable*'
        }

        It 'rejects an invalid -Type value' {
            { New-CCProperty -Name 'p' -Type 'Blob' } | Should -Throw
        }

        It 'accepts all valid -Type values' {
            foreach ($t in @('String','Int64','Double','DateTime','Boolean','StringCollection')) {
                { New-CCProperty -Name 'p' -Type $t } | Should -Not -Throw
            }
        }
    }

    Context 'optional fields' {
        It 'includes labels when -Retrievable and -Labels are set' {
            $r = New-CCProperty -Name 'p' -Type 'String' -Retrievable -Labels @('title','url')
            $r.labels | Should -Be @('title','url')
        }

        It 'omits labels key when none are provided' {
            $r = New-CCProperty -Name 'p' -Type 'String' -Retrievable
            $r.ContainsKey('labels') | Should -BeFalse
        }

        It 'includes aliases when -Aliases is set' {
            $r = New-CCProperty -Name 'p' -Type 'String' -Aliases @('a1','a2')
            $r.aliases | Should -Be @('a1','a2')
        }

        It 'omits aliases key when none are provided' {
            $r = New-CCProperty -Name 'p' -Type 'String'
            $r.ContainsKey('aliases') | Should -BeFalse
        }

        It 'includes isExactMatchRequired when -ExactMatchRequired is set' {
            $r = New-CCProperty -Name 'p' -Type 'String' -ExactMatchRequired
            $r.isExactMatchRequired | Should -BeTrue
        }

        It 'omits isExactMatchRequired when not set' {
            $r = New-CCProperty -Name 'p' -Type 'String'
            $r.ContainsKey('isExactMatchRequired') | Should -BeFalse
        }
    }
}
