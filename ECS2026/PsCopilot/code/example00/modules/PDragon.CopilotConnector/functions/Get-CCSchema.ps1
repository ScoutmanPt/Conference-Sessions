function Get-CCSchema {
    [CmdletBinding()]
    param(
        [switch] $Example1
    )

    if (-not $Example1) {
        throw "Specify -Example1 to create the sample REST Countries schema."
    }

    @(
        New-CCProperty -Name "name" -Type "String" -Queryable -Searchable -Retrievable -Labels @("title")
        New-CCProperty -Name "region" -Type "String" -Queryable -Searchable -Retrievable
        New-CCProperty -Name "subregion" -Type "String" -Queryable -Searchable -Retrievable
        New-CCProperty -Name "capital" -Type "String" -Queryable -Searchable -Retrievable
        New-CCProperty -Name "population" -Type "Int64" -Retrievable
        New-CCProperty -Name "latitude" -Type "Double" -Retrievable
        New-CCProperty -Name "longitude" -Type "Double" -Retrievable
        New-CCProperty -Name "areaInSqKm" -Type "Int64" -Retrievable
        New-CCProperty -Name "timezone" -Type "String" -Retrievable
        New-CCProperty -Name "mapUrl" -Type "String" -Retrievable -Labels @("url")
        New-CCProperty -Name "flagUrl" -Type "String" -Retrievable
        New-CCProperty -Name "borders" -Type "String" -Retrievable
        New-CCProperty -Name "languages" -Type "String" -Retrievable
        New-CCProperty -Name "currencies" -Type "String" -Retrievable
        New-CCProperty -Name "lastModifiedBy" -Type "String" -Queryable -Searchable -Retrievable -Labels @("lastModifiedBy")
        New-CCProperty -Name "lastModifiedDateTime" -Type "DateTime" -Queryable -Retrievable -Refinable -Labels @("lastModifiedDateTime")
    )
}
