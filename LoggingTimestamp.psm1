<#
.SYNOPSIS
Writes a color-coded timestamp to console - useful for logging transcripts.
#>
function Get-Timestamp
{
    [alias('Write-Timestamp','timestamp','logtime','log')]
    param(
        [validateset('start','start log','end','end log','information',
            'change','warning','notice','error',"error`t",'whatif')]
        [string]$logType = 'information',
        [string]$message
    )

    # Defines an empty out string, default write color, and flips noNewLine to true for writing log message
    [string]$outString  = $null
    [string]$outColor   = 'White'
    [bool]$noNewLine    = $true

    # Defines a standard start log message & ensures noNewLine is not flipped when log output is written
    if($logType -match '^start')
    {
        $outString  = "START LOG:`t$(Get-Date -Format 'MM/dd/yyyy hh:mm:ss tt')"
        $outColor   = 'White'
        $noNewLine  = $false
    }
    # Defines a standard end log message & ensures noNewLine is not flipped when log output is written
    elseif($logType -match '^end')
    {
        $outString  = "END LOG:`t$(Get-Date -Format 'MM/dd/yyyy hh:mm:ss tt')"
        $outColor   = 'White'
        $noNewLine  = $false
    }
    # For all other log types, defines the string prefix & output colors
    else{        
        # Log timestamp prefixes use different number of tabs to keep text rows aligned properly
        if($logType -match '^error|^change$|^notice$|^whatif$')
        {$tagString = "`t$($logType.ToUpper() -replace '\s+'):`t`t"}
        else{$tagString = "`t$($logType.ToUpper()):`t"}

        # Defines write-host foreground color values
        switch($logType)
        {
            'information'           {$outColor  = 'Magenta'}
            'change'                {$outColor  = 'Cyan'}
            'warning'               {$outColor  = 'Yellow'}
            'notice'                {$outColor  = 'Yellow'}
            {$_ -match '^error'}    {$outColor  = 'Red'}

            default         {$outColor = 'White'}
        }

        # Defines the outString based on log type & appends the message if one was passed into cmd
        $outString = "$(Get-Date -Format 'hh:mm:ss tt')$tagString"
        if($message)
        {
            $outString += $message
            $noNewLine  = $false
        }
    }

    # Defines the hash table for Write-Host cmd splatting
    $writeHostHash = @{
        Object          = $outString
        ForegroundColor = $outColor
        NoNewLine       = $noNewLine
    }
    # Writes timestamp message to console w/values defined in writeHostHash hashtable
    Write-Host @writeHostHash
}
