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

    #Initializes ValuesToRemove as an empty object to append null / empty values
    $ValuesToRemove = @()
    
    #Uses GetEnumerator function on the input hash table to check Keys for null / empty Values
    $InputHashTable.GetEnumerator() | 
        ForEach-Object{
            #If the current Key Value is null or empty, the Key's name is appended to the ValuesToRemove object
            if($null -eq $_.Value -or $_.Value -eq '')
            {$ValuesToRemove += $_.Name}
        }

    #Loops through each item of the ValuesToRemove object and removes the Key from the InputHashTable
    $ValuesToRemove | ForEach-Object {$InputHashTable.Remove("$_")}

    #Returns the InputHashTable
    $InputHashTable
}
