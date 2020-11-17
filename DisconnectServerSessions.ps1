#Requires -Modules ActiveDirectory

param(
    [string]$ADUsername = $env:USERNAME,
    # Excludes local host from search - prevents resetting current session if IncludeActiveSessions switch flipped
    [string[]]$ComputerName = (Get-ADComputer -Filter {OperatingSystem -like '*server*'} | 
        Where-Object {$_.Name -ne $env:COMPUTERNAME}).Name,

    [alias('IncludeActive')]
    [switch]$IncludeActiveSessions,
#    [pscredential]$Credential,
    [alias('HideWarnings')]
    [switch]$SuppressWarnings,

    [switch]$WhatIf,
    [switch]$Confirm
)

############################## TIMESTAMP FUNCTION ##############################
function Get-Timestamp
{
    param(
        [validateset('start','start log','end','end log','information',
            'change','warning','error',"error`t")]
        [string]$logType = 'information'
    )

    switch($logType)
    {
        'start' {"START LOG:`t$(Get-Date -Format 'MM/dd/yyyy hh:mm:ss tt')"}
        'end' {"END LOG:`t$(Get-Date -Format 'MM/dd/yyyy hh:mm:ss tt')"}

        default {        
            if($logType -eq 'error' -or $logType -eq 'change')
            {$tagString = "`t$($logType.ToUpper()):`t`t"}
            else{$tagString = "`t$($logType.ToUpper()):`t"}

            "$(Get-Date -Format 'hh:mm:ss tt')$tagString"
        }
    }
}
################################################################################

# Specifies a filter to exclude items that didn't have a value under Username
#    No Username value shifted "State" value ito the ID field; this allows the where-object to ignore those results.
# $filter = {$_.ID -notmatch 'Disc' -and $_.ID -notmatch 'Conn' -and $_.ID -notmatch 'Listen'}
[string]$filterString = "`$_.Username -eq `$ADUsername"
if(!$IncludeActiveSessions){$filterString += " -and `$_.State -ne 'Active'"}
[scriptblock]$filter = [scriptblock]::Create($filterString)

[int]$totalComputers = ($ComputerName | Measure-Object).Count
[int]$computerNum = 0

# Loops through each remote machine in the ComputerName array
foreach($Computer in $ComputerName)
{
    # Increments the number of computer being processed & writes current progress
    $computerNum++
    Write-Progress -Activity 'Checking sessions on remote computers' -Status "Checking system `"$Computer`"" `
        -PercentComplete (($computerNum/$totalComputers) * 100)

    # Resets UserSession & serverPing on each loop
    $UserSession = @()
    [bool]$serverPing = $false
    # Checks to see if remote system is online & reachable
    $serverPing = Test-NetConnection $Computer -InformationLevel Quiet -WarningAction SilentlyContinue

    # Only attempts collecting session info / resetting sessions if server reachable
    if($serverPing)
    {
        #Runs Query Session against the specified computer & parses output
        $UserSession = (Query Session /Server:$Computer) -replace '^.' -replace '^\s+',',' -replace '\s+',',' | 
            #Converts the parsed text to a PSObject & filters out items w/no Username values
            ConvertFrom-Csv | Where-Object $filter | Select-Object Username, ID, State, 
                @{Name='RemoteSystem';Expression={$Computer}}
        # If a session matching the filter criteria is found on the remote machine
        if($UserSession)
        {
            # If the WhatIf switch is used, outputs to console without making any changes
            if($WhatIf)
            {
                Write-Host "What If:`tResetting session `"$($UserSession.ID)`" on system `"$($UserSession.RemoteSystem)`" for user `"$($UserSession.Username)`"" `
                    -ForegroundColor White
            }
            # If the confirm switch is used, requests verification before making any changes
            elseif($Confirm)
            {
                # Resets the validResponse bool on each loop
                [bool]$validResponse = $false
                # Loops until a valid response is provided
                do{
                    # Checks if user input is valid - if 'y' resets session, if 'n' notifies running user w/o making any changes
                    try{
                        [char]$userResponse = Read-Host -Prompt "Would you like to reset session `"$($UserSession.ID)`" on system `"$($UserSession.RemoteSystem)`" for user `"$($UserSession.Username)`""

                        switch($userResponse)
                        {
                            'y' {
                                $validResponse = $true

                                Write-Host "$(Get-Timestamp 'change')Resetting session session `"$($UserSession.ID)`" on system `"$($UserSession.RemoteSystem)`" for user `"$($UserSession.Username)`"" `
                                    -ForegroundColor Cyan
                                Reset Session $($UserSession.Id) /Server:$($UserSession.RemoteSystem)
                            }
                            'n' {
                                $validResponse = $true

                                Write-Host "$(Get-Timestamp)Session session `"$($UserSession.ID)`" on system `"$($UserSession.RemoteSystem)`" for user `"$($UserSession.Username)`" will not be reset or disconnected" `
                                    -ForegroundColor Magenta
                            }

                            # If invalid response, throws error to jump to catch block
                            default{throw}
                        }
                    }
                    # Notifies running user of invalid response
                    catch{
                        $validResponse = $false
                        Write-Host "$(Get-Timestamp 'warning')You have entered an invalid value, please try again" `
                            -ForegroundColor Yellow
                    }
                }until($validResponse)
            }
            # If no WhatIf or Confirm switches, resets remote server session
            else{
                Write-Host "$(Get-Timestamp 'change')Resetting session session `"$($UserSession.ID)`" on system `"$($UserSession.RemoteSystem)`" for user `"$($UserSession.Username)`"" `
                    -ForegroundColor Cyan
                Reset Session $($UserSession.Id) /Server:$($UserSession.RemoteSystem)
            }
        }
    }
    # If no successful ping, writes to console that server not found
    else{
        if(!$SuppressWarnings)
        {
            Write-Host "$(Get-Timestamp 'warning')Ping test failed for `"$Computer`"" `
                -ForegroundColor Yellow
        }
    }
}
