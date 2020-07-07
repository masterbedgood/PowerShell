<#
.SYNOPSIS
Replaces specified header(s) with corresponding NewHeader values in provided InputCSV

.DESCRIPTION
Replaces the specified header(s) in a csv pscustom object with the provided new header values.
Header values must be provided in the same order as the headers being replaced.
The number of values provided for OldHeader and NewHeader must be equal.

.EXAMPLE
$TestCsv = Import-Csv C:\Temp\Test.csv
Update-CsvHeader -OldHeader 'Test1','Test2' -NewHeader 'NewHeader1','NewHeader2' -InputCsv $TestCsv

Updates header 'Test1' to 'NewHeader1' and 'Test2' to 'NewHeader2' in TestCsv - returns updated object
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
    #$CSVHeaders = ($InputCSV | Get-Member -MemberType NoteProperty).Name
    #Replaced GM w/PSObject.Properties.Name to preserve header order:  
    #   https://stackoverflow.com/a/27361641/13853660
    $CSVHeaders = $InputCSV[0].PSObject.Properties.Name

    ################################
    ### REPLACE HEADERS BY INDEX ###
    ################################

    #Loops through each header to replace until the i int equals the number of headers
    for($i=0; $i -lt $HeaderCount;  $i++)
    {
        #Updates the Headers arrays
        $SelectionHeaders = $CSVHeaders | Where-Object {$_ -ne $OldHeader[$i]}
        #Replaces old header w/new header - allows for preserving header order in updated return object
        $CSVHeaders = $CSVHeaders -replace $OldHeader[$i],$NewHeader[$i]

        $InputCSV = $InputCSV | 
            Select-Object @($SelectionHeaders + @{Name=$NewHeader[$i]; Expression={$_."$($OldHeader[$i])"}}) | 
            Select-Object $CSVHeaders
    }

    $InputCSV
}
