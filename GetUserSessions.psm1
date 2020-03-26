<#
.SYNOPSIS
Parses output from Query Session and returns a PSObject of current sessions
#>
function Get-UserSessions
{
    param(
        [string[]]$ComputerName
    )

    <#
        Specifies a filter to exclude items that didn't have a value under Username
        No Username value shifted "State" value ito the ID field; this allows the where-object to ignore those results.
    #>
    $Filter = {$_.ID -notmatch 'Disc' -and $_.ID -notmatch 'Conn' -and $_.ID -notmatch 'Listen'}
    
    #Runs a foreach loop against all computers provided in the ComputerName array
    $ComputerName | ForEach-Object {
        #Assigns the current loop value to the RemoteSysName var
        $RemoteSysName = $_

        #Runs Query Session against the specified computer & parses output
        (Query Session /Server:$RemoteSysName) -replace '^.' -replace '^\s+',',' -replace '\s+',',' | 
            #Converts the parsed text to a PSObject & filters out items w/no Username values
            ConvertFrom-Csv | Where-Object $Filter | Select-Object Username, ID, State, 
                @{Name='RemoteSystem';Expression={$RemoteSysName}}
    }
}
