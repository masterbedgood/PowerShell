<#
.SYNOPSIS
Parses returned text from 'vssadmin list writers' cmd and creates PSObject that can be passed to additional commands.
#>
function Get-VSSWriters
{
    #Assigns text result of 'vssadmin list writers' cmd to Writers var
    $Writers = vssadmin list writers

    #Parses the Writers string & assigns each matching line as a value in the WritersHash hash table
    $WritersHash = @{
        WriterName = ($Writers | Select-String 'Writer name:') -replace 'Writer name: ' -replace "'"
        WriterID = ($Writers | Select-String 'Writer Id') -Replace 'Writer Id:' -Replace '^\s+'
        WriterInstanceID = ($Writers | Select-String 'Writer Instance Id') -Replace 'Writer Instance Id:' -Replace '^\s+'
        State = ($Writers | Select-String 'State: ') -Replace 'State: ' -Replace '^\s+'
        LastError = ($Writers | Select-String 'Last error') -Replace 'Last error:' -Replace '^\s+'
    }

    #Initializes int vars i and iMax to specify the array item and max loop range for While loop
    [int]$i = 0
    [int]$iMax = (($WritersHash.WriterName | Measure-Object).Count - 1)

    #Loops through each item in the hash table & breaks the values apart into a new PSObject
    while($i -le $iMax)
    {
        #Uses int var i to specify which key value to return for each returned PSObject
        New-Object PSObject -Property @{
            WriterName = $WritersHash.WriterName[$i]
            WriterID = $WritersHash.WriterID[$i]
            WriterInstanceID = $WritersHash.WriterInstanceID[$i]
            State = $WritersHash.State[$i]
            LastError = $WritersHash.LastError[$i]
        } | Select-Object WriterName,WriterID,WriterInstanceID,State,LastError

        #Increments int var i
        $i++
    }
}
