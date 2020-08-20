<#
.SYNOPSIS
Searches AD for deleted objects matching search criteria.
Returned GUID can be used with Restore-ADObject:
    Get-DeletedADObjects -SamAccountName 'john.doe' | %{
        Restore-ADObject -Identity $_.ObjectGUID
    }
.PARAMETER ObjectName
The name of the deleted object - if a user, use the Surname / LastName value.
#>
function Get-DeletedADObjects
{
    param(
        [validateSet('user','computer','contact','container','group','organizationalUnit')]
        [alias('ObjectType')]
        [string[]]$ObjectClass,
        [string[]]$ObjectName,
        [alias('ADUsername')]
        [string[]]$SamAccountName,

        [alias('AdminCred','Cred')]
        [pscredential]$Credential
    )

    # If a value exists in the ObjectClass
    if($ObjectClass)
    {
        # Selects only the unique values for the ObjectClasses
        $ObjectClass = $ObjectClass | Sort-Object -Unique
        # Creates a new filter string joining all object class values
        $ObjectClassFilterString = "objectClass -eq '$([string]::join("' -or objectClass -eq '",$ObjectClass))'"
    }

    # If a value exists in the ObjectName
    if($ObjectName)
    {
        # Selects only the unique values for the ObjectName
        $ObjectName = $ObjectName | Sort-Object -Unique
        # Creates a new filter string joining all object name values
        $ObjectNameFilterString = "Name -like '*$([string]::join("*' -or Name -like '*",$ObjectName))*'"
    }

    # If a value exists in the SamAccountName
    if($SamAccountName)
    {
        # Selects only the unique values for the SamAccountName
        $SamAccountName = $SamAccountName | Sort-Object -Unique
        # Creates a new filter string joining all SamAccountName values
        $SamAccountNameFilterString = "SamAccountName -eq '$([string]::join("' -or SamAccountName -eq '",$SamAccountName))'"
    }

    if($ObjectClassFilterString -or $ObjectNameFilterString -or $SamAccountNameFilterString)
    {
        [string[]]$SearchStringArray = $ObjectClassFilterString, $ObjectNameFilterString, $SamAccountNameFilterString | 
            Where-Object {$_}

        $SearchString = "($([string]::join(") -and (", $SearchStringArray)))"
    }

    # Creates a SearchFilter with the values inside the SearchString
    if($SearchString){$SearchFilter = "$SearchString -and (Deleted -like '*')"}
    # If no ObjectClass or ObjectName values provided, creates a filter for only deleted items
    else{$SearchFilter =  "Deleted -like '*'"}
    
    #Creates a hash table for cmdlet splatting
    $ADObjectHash = @{        
        # Specifies properties to include (* = all)
        Properties = '*'
        # Includes deleted items
        IncludeDeletedObjects = $true
        # Creates a script block of the SearchFilter string & assigns to the -Filter param
        Filter = [Scriptblock]::Create($SearchFilter)
    }
    # If a value exists in the Credential parameter, assigns to the -Credential param for Get-ADObject
    if($Credential){$ADObjectHash.Credential = $Credential}

    # Searches AD for deleted items matching the SearchFilter
    Get-ADObject @ADObjectHash | ForEach-Object{
        # Creates an updated return object with only the desired properties
        New-Object PSObject -Property @{
            # If no value in SamAccountName (e.g. MailContact), tries to use the MailNickname value
            SamAccountName = &{if($_.SamAccountName){$_.SamAccountName}else{$_.MailNickname}}
            # Grabs the Name value & splits at the line break - selects 0 index to remove the "DEL: GUID" string
            Name = ($_.Name -split '\n')[0]
            # The deleted object's class
            ObjectClass = $_.ObjectClass
            # Shows that it's a deleted object
            Deleted = $_.Deleted
            # Employee ID if the value exists
            EmployeeID = $_.EmployeeID
            # Returns the ObjectGUID - can be used for a recovery deleted object
            ObjectGUID = $_.ObjectGUID
            # Shows the last modify timestamp for the AD Object
            ModifiedTimeStamp = $_.ModifyTimeStamp
        }
    }
}

<#
.SYNOPSIS
Gets a list of ADObject Classes
#>
function Get-ADObjectClass
{
    [alias('List-ADObjectClass')]
    param()
    Get-ADObject -filter * |
        Select-Object objectClass -Unique | 
            Sort-Object objectClass
}
