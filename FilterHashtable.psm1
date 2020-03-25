<#
.SYNOPSIS
    Filters null values from input hash table & returns hashtable object
#>
function Remove-NullValuesFromHash
{
    [alias('Filter-HashTable')]
    param(
        [parameter(Mandatory=$true,Position=0)]
        [hashtable]$InputHashTable
    )

    $ValuesToRemove = @()
    $InputHashTable.GetEnumerator() | 
        ForEach-Object{
            if($null -eq $_.Value -or $_.Value -eq '')
            {$ValuesToRemove += $_.Name}
        }

    $ValuesToRemove | ForEach-Object {$InputHashTable.Remove("$_")}

    $InputHashTable
}
