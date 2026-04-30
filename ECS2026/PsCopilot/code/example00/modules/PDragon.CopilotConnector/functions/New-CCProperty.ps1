function New-CCProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,
        [Parameter(Mandatory)]
        [ValidateSet("String", "Int64", "Double", "DateTime", "Boolean", "StringCollection")]
        [string] $Type,
        [switch] $Searchable,
        [switch] $Queryable,
        [switch] $Retrievable,
        [switch] $Refinable,
        [switch] $ExactMatchRequired,
        [string[]] $Labels = @(),
        [string[]] $Aliases = @()
    )

    if ($Searchable -and $Refinable) {
        throw "Property '$Name' cannot be both searchable and refinable."
    }

    if ($Labels.Count -gt 0 -and -not $Retrievable) {
        throw "Property '$Name' must be retrievable before semantic labels can be assigned."
    }

    $property = @{
        name          = $Name
        type          = $Type
        isSearchable  = [bool]$Searchable
        isQueryable   = [bool]$Queryable
        isRetrievable = [bool]$Retrievable
        isRefinable   = [bool]$Refinable
    }

    if ($ExactMatchRequired) {
        $property.isExactMatchRequired = $true
    }

    if ($Labels.Count -gt 0) {
        $property.labels = $Labels
    }

    if ($Aliases.Count -gt 0) {
        $property.aliases = $Aliases
    }

    $property
}
