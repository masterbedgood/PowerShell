function Get-Timestamp
{
    [alias('Write-Timestamp','timestamp','logtime','log')]
    param(
        [validateset('start','start log','end','end log','information',
            'change','warning','notice','error',"error`t")]
        [string]$logType = 'information',
        [string]$message
    )

    [string]$outString  = $null
    [string]$outColor   = 'White'
    [bool]$noNewLine    = $true

    if($logType -match '^start')
    {
        $outString  = "START LOG:`t$(Get-Date -Format 'MM/dd/yyyy hh:mm:ss tt')"
        $outColor   = 'White'
        $noNewLine  = $false
    }
    elseif($logType -match '^end')
    {
        $outString  = "END LOG:`t$(Get-Date -Format 'MM/dd/yyyy hh:mm:ss tt')"
        $outColor   = 'White'
        $noNewLine  = $false
    }

    else{        
        if($logType -match '^error' -or $logType -eq 'change' -or $logType -eq 'notice')
        {$tagString = "`t$($logType.ToUpper() -replace '\s+'):`t`t"}
        else{$tagString = "`t$($logType.ToUpper()):`t"}

        switch($logType)
        {
            'information'           {$outColor  = 'Magenta'}
            'change'                {$outColor  = 'Cyan'}
            'warning'               {$outColor  = 'Yellow'}
            'notice'                {$outColor  = 'Yellow'}
            {$_ -match '^error'}    {$outColor  = 'Red'}

            default         {$outColor = 'White'}
        }

        $outString = "$(Get-Date -Format 'hh:mm:ss tt')$tagString"
        if($message)
        {
            $outString += $message
            $noNewLine  = $false
        }
    }

    $writeHostHash = @{
        Object          = $outString
        ForegroundColor = $outColor
        NoNewLine       = $noNewLine
    }
    
    Write-Host @writeHostHash
}
