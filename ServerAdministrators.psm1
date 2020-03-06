#Requires -Module ActiveDirectory

<#
.SYNOPSIS
Checks if psexec is present in System32 - if not, downloads PSTools & extracts, moves psexec & psexec64 to System32
#>
function Get-PSExec
{
    [Alias('Download-PSExec')]
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
Gets all Windows-based servers specified (if none specified, all Windows-based servers in the domain) and attempts to remotely check for members of the specified local group (default = Administrators).
.DESCRIPTION
Attempts to invoke Get-LocalGroupMember on all specified Windows-based servers in the domain.  (If none are specified, all Windows-based servers in Active Directory are checked.)
Attempts to gather members of specified local group - if none specified, uses default value of "Administrators."
If Get-LocalGroupMember fails, uses 'net localgroup' command and attempts to parse returned text.  
If Invoke-Command fails, attempts to gather information using psexec.  
Also performs network test (Test-NetConnection) against remote server.
Results for administrators, server name, and ping test are returned as an object that can be piped to additional commands (e.g. Export-Csv).
#>
function Get-ServerAdministrators
{
    [alias('Get-ServerGroupMember')]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [string[]]$Servers,
        [Parameter(Mandatory=$false, Position=1)]
        [string]$LocalGroup = 'Administrators',
        [Parameter(Mandatory=$false, Position=2)]
        [Alias('Join','JoinChar')]
        [string]$JoinDelimiter = "`n"
    )

    [ScriptBlock]$GroupFilter = {$_.Name -match 'domain admins' -or $_.Name -match 'Helpdesk Admins'}
    
    #Checks if psexec.exe exists locally in system32 - if not, downloads
    Write-Host "`nChecking for PSExec.`nIf not found, will download.`n" -ForegroundColor Yellow
    timeout -t 1 > $null
    Get-PSExec

    #If the running user is not a member of domain admins or help desk admins, prompts for administrative credentials
    if(!(Get-ADPrincipalGroupMembership $Env:Username | Where-Object $GroupFilter))
    {$Cred = Get-Credential}
    
    #If no servers have been specified, gets all 
    if($Servers)
    {
        #Gets all AD computers with 'Server' operating system
        $DomainServers = ($Servers | ForEach-Object {Get-ADComputer $_ -Properties operatingsystem})
    }
    else{$DomainServers = Get-ADComputer -filter {operatingsystem -like '*server*'} -Properties operatingsystem}
    
    <#
    #$LocalGroupFilter fails when running as standard user & has been removed
    
    $LocalGroupFilter = {$_ -and $_ -notmatch 'PsExec' -and $_ -notmatch 'copyright' -and $_ -notmatch 'sysinternals.com' `
    -and $_ -notmatch 'alias name' -and $_ -notmatch '^comment' -and $_ -notmatch '^Members' `
    -and $_ -notmatch '-------------' -and $_ -notmatch 'command completed successfully'}
    #>

    #Script block to attempt to get local administrators on remote system    
    $ScriptBlock = {
        try{
            Get-LocalGroupMember $args[1] -ErrorAction Stop
        }
        catch{
            Write-Warning "Get-LocalGroupMember failed on $($args[0]).  Attempting 'net localgroup'"
            $AdminString = net localgroup $args[1]
            $AdminString | Where-Object {$_ -and $_ -notmatch 'PsExec' -and $_ -notmatch 'copyright' -and $_ -notmatch 'sysinternals.com' `
                                        -and $_ -notmatch 'alias name' -and $_ -notmatch '^comment' -and $_ -notmatch '^Members' `
                                        -and $_ -notmatch '-------------' -and $_ -notmatch 'command completed successfully'} | ConvertFrom-Csv -Header 'Name'
        }
    }

    if($Cred)
    {
        $AdminUsername = $Cred.UserName
        $AdminPassword = $Cred.GetNetworkCredential().Password
    }
    
    #Empty object to append results
    $AdminReport = @()
    
    ForEach($Server in $DomainServers)
    {
        #Resets LoopCSV
        $LoopCSV = @()
        
        [string]$ServerName = $Server.Name

        $InvokeParams = @{
            ComputerName = $ServerName
            ScriptBlock = $ScriptBlock
            ErrorAction = 'Stop'
        }
        if($Cred){$InvokeParams.Add('Credential',$Cred)}
        
        try{
            $LoopCSV = Invoke-Command @InvokeParams -ArgumentList $ServerName,$LocalGroup
        }
        catch{
            
            Write-Warning "Invoke-Command failed on $ServerName.  Attempting psexec."
            
            if($Cred)
            {
                $AdminString = psexec \\$ServerName -u $AdminUsername -p "$AdminPassword" net localgroup $LocalGroup
                $LoopCSV = $AdminString | Where-Object $LocalGroupFilter | ConvertFrom-Csv -Header 'Name'
            }
            else {    
                $AdminString = psexec \\$ServerName net localgroup $LocalGroup
                $LoopCSV = $AdminString | Where-Object $LocalGroupFilter | ConvertFrom-Csv -Header 'Name'
            }
        }

        $AdminReport += New-Object psobject -Property @{
            $LocalGroup = ForEach-Object{
                if(($LoopCSV.Name | Measure-Object).Count -ge 1)
                {[string]::Join($JoinDelimiter, $LoopCSV.Name)}
                else{$null}
            }
            ServerName = $ServerName
            PingSucceeded = ForEach-Object{
                (Test-NetConnection $ServerName).PingSucceeded
            }
        }
    }

    #Selects output by order of ServerName, LocalGroup name, and PingSucceeded; updates LocalGroup name to title case for reporting readability.
    $AdminReport | Select-Object ServerName, @{Name = (Get-Culture).TextInfo.ToTitleCase($LocalGroup); Expression = {$_.$LocalGroup}}, PingSucceeded
}

#Psexec fails w/access denied running as std user; special characters cause issues when attempting to use cmdkey /add:<target> to resolve this
#https://stackoverflow.com/questions/828432/psexec-access-denied-errors
