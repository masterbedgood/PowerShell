function Get-VSSWriters
{
    $Writers = vssadmin list writers

    $WritersHash = @{
        WriterName = ($Writers | Select-String 'Writer name:') -replace 'Writer name: ' -replace "'"
        WriterID = ($Writers | Select-String 'Writer Id') -Replace 'Writer Id:' -Replace '^\s+'
        WriterInstanceID = ($Writers | Select-String 'Writer Instance Id') -Replace 'Writer Instance Id:' -Replace '^\s+'
        State = ($Writers | Select-String 'State: ') -Replace 'State: ' -Replace '^\s+'
        LastError = ($Writers | Select-String 'Last error') -Replace 'Last error:' -Replace '^\s+'
    }

    $i = 0
    $iMax = (($WritersHash.WriterName | Measure-Object).Count - 1)

    $VssObj = @()

    while($i -le $iMax)
    {
        New-Object PSObject -Property @{
            WriterName = $WritersHash.WriterName[$i]
            WriterID = $WritersHash.WriterID[$i]
            WriterInstanceID = $WritersHash.WriterInstanceID[$i]
            State = $WritersHash.State[$i]
            LastError = $WritersHash.LastError[$i]
        } | Select-Object WriterName,WriterID,WriterInstanceID,State,LastError

        $i++
    }
}