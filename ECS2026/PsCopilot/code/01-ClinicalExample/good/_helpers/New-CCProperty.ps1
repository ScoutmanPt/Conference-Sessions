function New-CCProperty {
<#
.SYNOPSIS
    Creates a schema property definition hashtable for a Copilot connector.

.DESCRIPTION
    Builds a property hashtable compatible with the Microsoft Graph external connection
    schema format. Used with Get-CCSchema or directly when building a custom schema
    to pass to New-CCConnection.

.PARAMETER Name
    The internal name of the property (used in Graph API calls and search queries).

.PARAMETER Type
    The data type of the property. Valid values: String, Int64, Double, DateTime,
    Boolean, StringCollection.

.PARAMETER Searchable
    Makes the property full-text searchable. Cannot be combined with -Refinable.

.PARAMETER Queryable
    Allows the property to be used in keyword query language (KQL) queries.

.PARAMETER Retrievable
    Includes the property in search result data returned to the client.

.PARAMETER Refinable
    Allows the property to be used as a refinement filter. Cannot be combined with -Searchable.

.PARAMETER ExactMatchRequired
    Requires an exact string match when querying this property.

.PARAMETER Labels
    One or more semantic labels (e.g. 'title', 'url', 'lastModifiedBy') that help
    Microsoft 365 understand the meaning of the property. Requires -Retrievable.

.PARAMETER Aliases
    Alternative names for the property used in search queries.

.OUTPUTS
    [hashtable] A property definition hashtable.

.EXAMPLE
    New-CCProperty -Name 'name' -Type 'String' -Queryable -Searchable -Retrievable -Labels @('title')

.EXAMPLE
    New-CCProperty -Name 'population' -Type 'Int64' -Retrievable -Refinable
#>
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

    # --- Validation ---
    if ($Searchable -and $Refinable) {
        throw "Property '$Name' cannot be both searchable and refinable."
    }

    if ($Labels.Count -gt 0 -and -not $Retrievable) {
        throw "Property '$Name' must be retrievable before semantic labels can be assigned."
    }

    # --- Build property hashtable ---
    $property = @{
        name          = $Name
        type          = $Type
        isSearchable  = [bool]$Searchable
        isQueryable   = [bool]$Queryable
        isRetrievable = [bool]$Retrievable
        isRefinable   = [bool]$Refinable
    }

    # --- Optional fields ---
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
