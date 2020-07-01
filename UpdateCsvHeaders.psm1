<#
.SYNOPSIS
Replaces specified header(s) with corresponding NewHeader values in provided InputCSV
#>
function Update-CSVHeader
{
    [alias('Replace-CsvHeader')]
    param(
        [parameter(Mandatory=$true)]
        [string[]]$OldHeader,
        [parameter(Mandatory=$true)]
        [string[]]$NewHeader,
        [parameter(Mandatory=$true)]
        [pscustomobject]$InputCSV
    )

    ######################
    ### VERIFY INDEXES ###
    ######################
    if($OldHeader.Count -ne $NewHeader.Count)
    {throw "The input header counts do not match."}
    else{$HeaderCount = $OldHeader.Count}

    ###############################
    ### GET CURRENT CSV HEADERS ###
    ###############################
    $CSVHeaders = ($InputCSV | Get-Member -MemberType NoteProperty).Name

    ################################
    ### REPLACE HEADERS BY INDEX ###
    ################################

    #Loops through each header to replace until the i int equals the number of headers
    for($i=0; $i -lt $HeaderCount;  $i++)
    {
        #Updates the Headers arrays
        $SelectionHeaders = $CSVHeaders | Where-Object {$_ -ne $OldHeader[$i]}
        $CSVHeaders = $SelectionHeaders + $NewHeader[$i]

        $InputCSV = $InputCSV | Select-Object @($SelectionHeaders + @{Name=$NewHeader[$i]; Expression={$_."$($OldHeader[$i])"}})
    }

    $InputCSV
}
