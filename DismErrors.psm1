function Get-DismErrors
{
    Get-Content C:\Windows\Logs\DISM\dism.log | Select-String ', error' | 
        ForEach-Object{
            $ErrorObj = $_ -split ', error' -replace '^\s+' -replace '^dism\s+'
            $MessageObj = $ErrorObj[1] -split ': ',2
            New-Object psobject -Property @{
                Timestamp = $ErrorObj[0]
                DismUtility = $MessageObj[0]
                ErrorMessage = $MessageObj[1]
            } | Select-Object Timestamp,DismUtility,ErrorMessage
        }
}