#Requires -modules ActiveDirectory
<#
.SYNOPSIS
Checks if psexec is present in System32 - if not, downloads PSTools & extracts, moves psexec & psexec64 to System32
#>
function Request-PSExec
{
    param(
        [string]$DownloadPath = "$env:userprofile\Downloads\PSTools_$(Get-Date -format MM_dd_yyyy)",
        [string]$ArchivePath = "$DownloadPath\PSTools.zip",
        [string]$ExtractPath = "$DownloadPath\PSTools",
        [string]$PSExecURL = "https://download.sysinternals.com/files/PSTools.zip",
        [string]$PSExecDest = (cmd /c echo %systemroot%\System32)
    )

    #Attempts to run the following command as running user - if fails, moves on to CatchBlock and tries to runas admin
    $MoveCommand = {Move-Item -Path $ExtractPath\psexec.exe, $ExtractPath\psexec64.exe -Destination $PSExecDest -Force -ErrorAction Stop}
    #CatchBlock defines passed arguments as parameters to enable the same structure as $MoveCommand
    $CatchBlock = {param($ExtractPath,$PSExecDest) Move-Item -Path $ExtractPath\psexec.exe, $ExtractPath\psexec64.exe -Destination $PSExecDest -Force}

    #If the psexec.exe is not found in the Windows\System32 dir, downloads, unzips, & moves file
    if(!$(Test-Path $PSExecDest\psexec.exe))
    {
        #If the download path doesn't exist, creates it
        if(!$(Test-Path $ExtractPath)){New-Item -Path $ExtractPath -ItemType Directory}
        
        #Downloads PSTools.zip & extracts files
        Invoke-WebRequest $PSExecURL -OutFile $ArchivePath
        Expand-Archive -Path $ArchivePath -DestinationPath $DownloadPath\PSTools
        
        #Attempts to move psexec & psexec64 to System32 - if fails, runs as admin in catch block
        try{Invoke-Command -Command $MoveCommand}
        catch{
            #https://it-trials.github.io/scripting/passing-a-scriptblock-with-arguments-to-a-new-powershell-instance.html
            Write-Warning "Move-Item failed; attempting as admin."
            timeout -t 1 > $null
            Start-Process PowerShell.exe -Verb RunAs -ArgumentList "-Command Invoke-Command -ScriptBlock {$CatchBlock} -ArgumentList $ExtractPath,$PSExecDest" -Wait -WindowStyle Hidden
        }

        #Cleans up downloaded files
        Remove-Item $DownloadPath -Force -Recurse
    }
}

<#
.SYNOPSIS
Checks specified remote system's registry for specified user's mapped network drives
#>
function Get-UserDriveMap
{
    [alias('Get-MappedDrive','Get-DriveMap')]
    param(
        [parameter(Mandatory=$true, Position=0)]
        [string]$ComputerName,
        [parameter(Mandatory=$true, Position=1)]
        [string]$ADUsername,

        [pscredential]$AdminCred,

        [string]$UserSID = (Get-ADUser $ADUsername).Sid.Value,
        [validateset('DriveLetter', 'UNCPath')]
        [string[]]$SelectProperties = ('DriveLetter', 'UNCPath')
        #[string]$ScriptExportPath = 'C:\Temp\psexecscriptblock.ps1'
    )

    #Specifies a script block to run with Invoke-Command if PSRemoting is enabled on remote system
    $ScriptBlock = {
            param(
            [string]$UserSID
        )

        #Maps the HKU registry hive as a PSDrive to search registry & hides output
        New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS | 
            Out-Null

        #Searches the specified user's Network reg subkey fore each drive letter & RemotePath value
        Get-ChildItem "HKU:\$UserSID\Network\" | ForEach-Object {
            New-Object psobject -Property @{
                DriveLetter = ($_.Name -split '\\' | Select-Object -last 1)
                UNCPath = $_.GetValue('RemotePath')
            }
        }
    }

    #If the specified computer is the local machine, runs script block & passes UserSID as the param value
    if($Env:COMPUTERNAME -match $ComputerName)
    {&$ScriptBlock -UserSID $UserSID}

    #If the specified system is not the local machine, runs ScriptBlock remotely w/Invoke-Command
    else{
        #Specifies parameter values with a hash table
        $InvokeHash = @{
            ComputerName = $ComputerName
            ScriptBlock = $ScriptBlock
            ArgumentList = $UserSID
            ErrorAction = 'Stop'
        }
        #If the AdminCred parameter contains a value, appends the 'Credential' parameter to the hash table
        if($AdminCred){$InvokeHash.Add('Credential',$AdminCred)}
        
        #Attempts to run script block against the remote system using Invoke-Command - PSRemoting must be enabled on the remote system
        try{Invoke-Command @InvokeHash | Select-Object $SelectProperties}
        catch{

            #If PSRemoting is disabled or the command otherwise fails, warns running user & retries using psexec
            Write-Warning "Invoke command failed on remote system - PSRemoting may be disabled."
            Write-Host "`nAttempting to run command with PSExec...`n"

            #Checks for PSExec & Downloads if missing (first function in this file)
            Request-PSExec

            ### DEFINES PSEXEC SCRIPT BLOCK ###
            <#
                PSExec argument cannot be over a certain character limit
                This script block is condensed with several aliases and parameter abbreviations
                ? = alias for Where-Object
                % = alias for ForEach-Object
                sls = alias for Select-String
                select -l = Select-Object -Last

                As PSExec returns information as a string, some of the parsed results may be inaccurate!
            #>
$PSExecBlock = {
param($SID)
reg query hku\$SID\Network | ? {$_} | %{
[string]::join(',',($($_ -split '\\' | select -l 1), ((reg query $_ | sls 'Remote') -split '\s+' | Select -L 1)))
}
}

            #If the AdminCred param has a value, passes that information through psexec
            #If the password contains an exit character, this command may fail
            if($AdminCred)
            {
                #Attempts to run powershell on the remote system with psexec; returned string is assigned to PSExecReturnText var
                #Runs Invoke-Command (icm) on the remote system with the PSExecBlock script block & passes the UserSid param value
                $PSExecReturnText = psexec.exe -u $AdminCred.Username -p $AdminCred.GetNetworkCredential().Password `
                                        \\$ComputerName -h powershell -command "icm {$PSExecBlock} -arg $UserSID" 
            }

            #If no admin creds, runs psexec w/no credential switches
            else{$PSExecReturnText = psexec.exe \\$ComputerName -h powershell -command "icm {$PSExecBlock} -arg $UserSID"}

            #If a value exists in the PSExecReturnText variable, parses for drive map info & assigns to PSExecReturnObject var
            if($PSExecReturnText)
            {
                #Select-String only selects strings beginning (^) with any character (.) followed by a comma (,)
                $PSExecReturnObject = $PSExecReturnText | Select-String '^.,' |
                                        ForEach-Object {
                                            $PSExecText = $_ -Split ','
                                            New-Object psobject -property @{
                                            DriveLetter = $PSExecText[0]
                                            UNCPath = $PSExecText[1]
                                            }
                                        }
            }

            #If PSExecReturnObject contains a value, selects the SelectProperties & returns to console as an object
            if($PSExecReturnObject)
            {$PSExecReturnObject | Select-Object $SelectProperties}
            #If no value in PSExecReturnObject, warns of failure & recommends retrying script in a PSSession under admin account
            else{
                Write-Warning "PSExec failed to complete the task; this may be due to an exit character in your password"
                Write-Host "Please try running the script as your admin user account to see if the issue persists." -ForegroundColor Yellow
            }
        }
    }
}
