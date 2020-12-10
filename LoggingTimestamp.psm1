<#
.SYNOPSIS
Writes a color-coded timestamp to console - useful for logging transcripts.
#>
function Get-Timestamp
{
    [alias('Write-Timestamp','timestamp','logtime','log')]
    param(
        [validateset('start','start log','end','end log','information', 'success',
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
            'success'               {$outColor  = 'Green'}
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

    # If format message function loaded in current session, updates the output message w/properly formatted log entry
    if([bool](Get-Command Format-LogMessage -ErrorAction Ignore))
    {$outString = Format-LogMessage $outString}

    # Defines the hash table for Write-Host cmd splatting
    $writeHostHash = @{
        Object          = $outString
        ForegroundColor = $outColor
        NoNewLine       = $noNewLine
    }
    # Writes timestamp message to console w/values defined in writeHostHash hashtable
    Write-Host @writeHostHash
}


<#
.SYNOPSIS
Replaces tabs with 8 spaces & measures total string length.  If updated string length exceeds 
#>
function Format-LogMessage
{
    # Splits at console width & resumes string on subsequent lines tabbed in appropriate distance
    param(
        [string]$messageString,
        [int]$tabSpaces = 8,
        [int]$numTabs = 4
    )

    [int]$consoleWidth = [System.Console]::WindowWidth
    [bool]$returnRevisedString = $false

    [string]$tabString = $null
    for($i=0; $i -lt $numTabs; $i++)
    {$tabString += "`t"}

    [string]$spaceString = $null
    for($i=0; $i -lt ($numTabs*$tabSpaces); $i++)
    {$spaceString+= ' '}

    [string]$singleTab = $null
    for($i=0; $i -lt ($tabSpaces); $i++)
    {$singleTab += ' '}

    # If the input string has a newline that starts with a tab, attempts to preserve input formatting
    if($messageString -match '\n\t')
    {
        [string]$revisedString = $null
        [string[]]$tempArray = $messageString -split '\n\t'
        
        for($i = 0; $i -lt ($tempArray | Measure-Object).count; $i++)
        {
            if($i -eq 0){$revisedString += $tempArray[$i]}
            else{$revisedString += "`n$spaceString$($tempArray[$i])"}
        }

        $returnRevisedString = $true
    }

    # Will attempt to parse & format input string if not matching newline tab
    else{
        [string]$revisedString = $messageString -replace '\n\t',"`t" -replace '\n\s+',' ' `
            -replace '\n',' ' -replace '\t',$singleTab
        
        $matchString = "\.[^\s+\t'`"]"
        if($revisedString -match $matchString)
        {
            [string[]]$matchArrays = $null
            $matchArrays = $revisedString -split "($matchString)" | Select-String $matchString |
                Where-Object {$messageString -notmatch "\$($_)"}| ForEach-Object {$_.ToString()}

            foreach($match in $matchArrays)
            {$revisedString = $revisedString -replace "\$match",". $($match.Substring(1,1))"}
        }

        if($revisedString.Length -gt $ConsoleWidth)
        {
            do{
                [string]$lastLine = ($revisedString -split "\n" | Select-Object -Last 1)

                [string[]]$tempArray = ($lastLine -replace "^$tabString","$spaceString").Substring(0, $consoleWidth) -split "(\s+)"
                [int]$tempArrayCount = ($tempArray | Measure-Object).Count
                if($tempArrayCount -gt 1)
                {
                    [string]$tempString =   [string]::Join('', ($tempArray | 
                                                Select-Object -First ($tempArrayCount - 1))) `
                                                    -replace "^$spaceString","$tabString"
                }
                else{[string]$tempString =   $tempArray[0]}

                $revisedString = (($revisedString -split "\n") `
                    -replace "^$($tempString -replace '\\','\\')","$tempString`n`t`t`t`t" | Out-String) -replace '\s+$'

                [string]$lastLine = ($revisedString -split "\n" | Select-Object -Last 1)
                [int]$lastLineLength = ($lastLine -replace "^$tabString","$spaceString").Length
            }until(($lastLineLength -le $consoleWidth) -or (($lastLine -replace '^\s+') -notmatch '\s+'))

            $returnRevisedString = $true
        }
    }

    if($returnRevisedString)
    {
        $revisedString = $revisedString -replace $singleTab,"`t"
        $revisedString
    }
    else{$messageString}
}


# https://poshoholic.com/2009/01/19/powershell-quick-tip-how-to-retrieve-the-current-line-number-and-file-name-in-your-powershell-script/
function Get-CurrentLineNumber {$MyInvocation.ScriptLineNumber}
# New-Alias -Name __LINE__ -Value Get-CurrentLineNumber –Description ‘Returns the current line number in a PowerShell script file.‘

function Get-CurrentFileName {
    param(
        [alias('fp','full')]
        [switch]$FullPath
    )
    [string]$ScriptName = $MyInvocation.ScriptName
    if($FullPath -and $ScriptName){$ScriptName}
    else{
        try{Split-Path $ScriptName -Leaf}
        catch{$null}
    }
}
