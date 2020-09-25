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
        [string]$JoinDelimiter = "`n",

        [alias('AdminCred','Cred')]
        [pscredential]$Credential
    )
    
    # LogonEventID for event log parsing
    [string]$LogonEventID = '4648'
    # Empty return object
    $ReturnObject = @()

    ###################################################
    ### SCRIPT BLOCK FOR APPENDING TO RETURN OBJECT ###
    ###################################################

    $AppendReturnObject = {
        param(
            [string]$AdminAccount,
            [string[]]$RemoteAdmins,
            $RemoteLogonEvents,
            [bool]$PingSucceeded,
            [string]$ServerName,
            $UserFolders
        )
        [string[]]$MemberOfGroup = $null
        [string]$AdminType = $null

        # Notifies running user of status
        Write-Host "Filtering LogonEvents from $ServerName - searching for account $AdminAccount..." `
            -ForegroundColor Magenta
        # Gets the newest logon event that matches the current loop Username in 'Message' value
        $LastLogonEvent = $RemoteLogonEvents | Where-Object {$_.Message -match "\s+$AdminAccount"} | 
            Select-Object -First 1

        # Looks at the LastWriteTime attribute on the user's C:\Users folder
        $UserFolderObj = $UserFolders | Where-Object {$_.Name -eq $AdminAccount}

        if($AdminAccount -ne 'Administrator')
        {
            try{
                if([bool](Get-ADUser $AdminAccount -ErrorAction stop))
                {
                    $AdminType = 'DomainUser'
                    $MemberOfGroup = Get-ADPrincipalGroupMembership $AdminAccount |
                        ForEach-Object{
                            ($_ | Where-Object {$RemoteAdmins -contains $_.SamAccountName}).SamAccountName
                        }
                    $MemberOfGroup = $MemberOfGroup | Where-Object {$_}
                }
            }
            catch{
                try{
                    if([bool](Get-ADGroup $AdminAccount -ErrorAction stop))
                    {$AdminType = 'ADGroup'}
                }
                catch{$AdminType = 'LocalUserOrGroup'}
            }
        }
        else{$AdminType = 'LocalUserOrGroup'}

        New-Object psobject -Property @{
            Server = $ServerName
            PingSucceeded = $PingSucceeded
            UserOrGroup = $AdminAccount
            IsAdmin = (&{if($MemberOfGroup -or ($RemoteAdmins -contains $AdminAccount)){$true}else{$false}})
            PulledFromFoldersList = (&{if($RemoteAdmins -notcontains $AdminAccount){$true}})
            AdminObjectType = $AdminType
            MemberOfGroup = (&{if(($MemberOfGroup | Measure-Object).Count -gt 1)
                    {[string]::join('; ',$MemberOfGroup)}
                    else{$MemberOfGroup}})
            LastLogonEvent = $LastLogonEvent.TimeWritten
            LastLogonEventID = $LastLogonEvent.InstanceID
            LastLogonEventIndex = $LastLogonEvent.Index
            LastLogonEventEntryType = $LastLogonEvent.EntryType
            UserFolderLastModified = $UserFolderObj.LastWriteTime
            UserFolderChildLastAccess = $UserFolderObj.LastAccess
        }
    }


    # Checks if psexec.exe exists locally in system32 - if not, downloads
    Write-Host "`nChecking for PSExec.`nIf not found, will download.`n" -ForegroundColor Yellow
    timeout -t 1 > $null
    Download-PSExec
    
    #If no servers have been specified, gets all 
    if($Servers)
    {
        #Gets all AD computers with 'Server' operating system
        $DomainServers = ($Servers | ForEach-Object {Get-ADComputer $_ -Properties operatingsystem})
    }
    else{$DomainServers = Get-ADComputer -filter {operatingsystem -like '*server*'} -Properties operatingsystem}
    

    #####################
    ### FILTER BLOCKS ###
    #####################

    # Defines filtering script block to remove PSExec info where Invoke-Command fails OR Get-LocalGroupMember not available
    [scriptblock]$LocalGroupFilter = {$_ -and $_ -notmatch 'PsExec' -and $_ -notmatch 'copyright' `
                            -and $_ -notmatch 'sysinternals.com' -and $_ -notmatch 'alias name' `
                                -and $_ -notmatch '^comment' -and $_ -notmatch '^Members' `
                                    -and $_ -notmatch '-------------' -and $_ -notmatch 'command completed successfully'}
    # Defines a script block filter for PSExec when pulling folder information... this is super redundant...
    [scriptblock]$PSExecFolderFilter = {$_ -and $_ -notmatch 'PsExec' -and $_ -notmatch 'copyright' `
                        -and $_ -notmatch 'sysinternals.com' -and $_ -notmatch 'alias name' `
                            -and $_ -notmatch '^comment' -and $_ -notmatch '^Members' `
                                -and $_ -notmatch '-------------' -and $_ -notmatch '\s+Directory\:\s+' `
                                    -and $_ -notmatch 'command completed successfully'}

    #Script block to attempt to get local administrators on remote system    
    $ScriptBlock = {
        param(
            [string]$LocalGroup,
            [string]$LocalGroupFilterString,
            [string]$LogonEventID = '4648'
        )
        # Converts the LocalGroupFilter (which is passed as string) back to ScriptBlock
        [scriptblock]$LocalGroupFilter = [scriptblock]::Create($LocalGroupFilterString)

        #########################
        ### GROUP MEMBERSHIPS ###
        #########################
        # Notifies running user of status
        Write-Host "Collecting members of `"$LocalGroup`" on `"$env:Computername`"..." -ForegroundColor Magenta
        # Attempts to pull local group info with Get-LocalGroupMember
        $GroupMembers = try{
                Get-LocalGroupMember $LocalGroup -ErrorAction Stop | 
                    Select-Object Name
            }
            # If Get-LocalGroupMember not recognized on target system, 
            catch{
                # Write-Warning "Get-LocalGroupMember failed on $ServerName.  Attempting 'net localgroup'"
                Write-Warning "Get-LocalGroupMember failed on $env:COMPUTERNAME.  Attempting 'net localgroup'"
                $AdminString = net localgroup $LocalGroup

                # Converts the net localgroup string output to a PSObject
                $AdminString | Where-Object $LocalGroupFilter | ConvertFrom-Csv -Header 'Name'
            }

        ##################
        ### EVENT LOGS ###
        ##################
        # Notifies running user of status
        Write-Host "Collecting Logon Events (ID = $LogonEventID) on `"$env:Computername`"..." -ForegroundColor Magenta
        # Script block to use for pulling logon events - may error if events are being cleared when first pulled
        $EventLogScriptBlock = {
            Get-EventLog -LogName Security -InstanceId $LogonEventID | 
                Select-Object Index, EntryType, InstanceID, Message, TimeWritten
            }

        # Attempts to pull logon events - may initially fail if events are being cleared when pulling
        $EventLogs = try{&$EventLogScriptBlock}catch{&$EventLogScriptBlock}

        ####################
        ### USER FOLDERS ###
        ####################
        # Notifies running user of status
        Write-Host "Collecting information on C:\Users folders on `"$env:Computername`"..." -ForegroundColor Magenta
        # Gets list of all folders under C:\Users
        $FolderList = Get-ChildItem C:\Users\
        # Loops through each folder & pulls the most recent LastAccessTime timestamp - converts to sho
        $UserFolders = foreach($Folder in $FolderList)
                        {
                            $LastAccess = $null
                            $LastAccess = ((Get-ChildItem $Folder.FullName -Recurse | 
                                    Sort-Object LastAccessTime -Descending
                                        ).LastAccessTime)[0].ToString('MM/dd/yyyy hh:mm')
                            $Folder | Select-Object Name, LastWriteTime, @{
                                Name = 'LastAccess'
                                Expression = {$LastAccess}
                            }
                        }

        # Returns parent object containing GroupMembers, EventLogs, and UserFolders objects
        New-Object PSObject -Property @{
            LocalServerAdmins = $GroupMembers
            LogonEvents = $EventLogs
            UserFolders = $UserFolders
        }
    }

    # Parses creds for psexec if value exists in $Credential
    if($Credential)
    {
        $AdminUsername = $Credential.UserName
        $AdminPassword = $Credential.GetNetworkCredential().Password
    }

    #Loops through each server in the DomainServers var - Assigns ONLY the Name attribue to ServerName loop obj
    ForEach($ServerName in $DomainServers.Name)
    {
        # Resets LoopObj, RemoteAdmins, RemoteLogonEvents, UserFolders, and ReturnObject on each loop
        $LoopObj = @()
        $RemoteAdmins = @()
        $RemoteLogonEvents = @()
        $UserFolders = @()
        $ReturnObject =  @()

        #Tests ping - if fails, does not attempt to grab admins on remote machine
        $PingSucceeded = [bool](Test-NetConnection $ServerName -InformationLevel Quiet -WarningAction 'SilentlyContinue')
        
        # Creates a hash table for invoke-command splatting
        $InvokeHash = @{
            ComputerName = $ServerName
            ScriptBlock = $ScriptBlock 
            ErrorAction = 'Stop' 
            ArgumentList = $LocalGroup, $LocalGroupFilter
        }
        #Only adds credential value if the variable containes a value
        if($Credential){$InvokeHash.Credential = $Credential}

        #Only attempts to grab admins if the ping was successful
        if($PingSucceeded)
        {
            # Attempts Invoke-Command on remote system; if fails, jumps to Catch which relies on psexec
            try{
                $LoopObj = Invoke-Command @InvokeHash
            }

            #If invoke command failed, attempts w/PSExec
############################################################################################################
### PSEXEC ### PSEXEC ### PSEXEC ###### PSEXEC ### PSEXEC ### PSEXEC ###### PSEXEC ### PSEXEC ### PSEXEC ###
############################################################################################################
            catch{
                #Warns running user of status
                Write-Warning "Invoke-Command failed on $ServerName.  Attempting psexec."

                # Defines a script block string for event log parsing through PSExec
                # Get-EventLog -LogName Security -InstanceID $LogonEventId | Format-List
                $PSExecEventScriptString = "Get-EventLog -LN Security -Ins $LogonEventID -ea SilentlyContinue | fl"

                ########################################## FOLDER PSEXEC SCRIPT ##########################################
                <#
                    Defines a scritp block string for grabging user folders & timestamps
                    Without Aliases, the following script is defined as:
                        Get-ChildItem C:\Users | ForEach-Object{
                            $Folder = $_
                            $LastAccess = $null
                            $LastAccess = (Get-ChildItem $Folder.FullName -Recurse |
                                Sort-Object LastAccessTime -Descending | Select-Object -first 1)
                            
                            $Folder | Select-Object Name, LastWriteTime, @{
                                Name = 'LastAccess'
                                Expression = {$LastAccess.LastAccessTime.ToString('MM/dd/yyyy hh:mm')}
                            }
                        } | Format-List

                    The -Split & -Replace removes newlines & whitespace used to make the script more readable
                #>
                ########################################## FOLDER PSEXEC SCRIPT ##########################################
                $FolderPSExecScriptString = [string]::Join('',("gci c:\users | `
                    %{`$Fol=`$_;`$Lacc=`$null; `
                        `$LAcc = (Gci `$_.Fullname -R | sort LastAccessTime -des | Select -Fi 1);
                            `$Fol|Select Name,LastWriteTime, `
                                @{n='LastAccess';e={`$LAcc.LastAccessTime.ToString('MM/dd/yyyy hh:mm')}}} | `
                                    FL" -split '\n' -replace '^\s+'))
                
                # Attempts psexec w/creds if value in var
                if($Credential)
                {
                    # Notifies running user of status
                    Write-Host "Collecting members of `"$LocalGroup`" on `"$ServerName`"..." -ForegroundColor Magenta
                    # Collects group members of remote system with net localgroup & returns values into string var
                    $AdminString = psexec -accepteula -nobanner \\$ServerName `
                        -u $AdminUsername -p "$AdminPassword" net localgroup $LocalGroup

                    # Notifies running user of status
                    Write-Host "Collecting Logon Events (ID = $LogonEventID) on `"$ServerName`"..." -ForegroundColor Magenta
                    # Collects logn events & returns values to string var
                    $FoldersPSExecString = psexec -accepteula -nobanner `
                        \\$ServerName -u $AdminUsername -p "$AdminPassword" `
                            powershell "&{$FolderPSExecScriptString}" | Where-Object $PSExecFolderFilter

                    # Notifies running user of status
                    Write-Host "Collecting information on C:\Users folders on `"$ServerName`"..." -ForegroundColor Magenta
                    # Grabs folder names & modify/access timestamps & returns to string var
                    $EventPSExecString = psexec -accepteula -nobanner `
                        \\$ServerName -u $AdminUsername -p "$AdminPassword" powershell "&{$PSExecEventScriptString}" |
                            Where-Object $PsexecFolderFilter
                }
                #if no value in Credential, uses psexec w/o specifying credentials & attempts to parse information
                else {    
                    # Notifies running user of status
                    Write-Host "Collecting members of `"$LocalGroup`" on `"$ServerName`"..." -ForegroundColor Magenta
                    # Collects group members of remote system with net localgroup & returns values into string var
                    # Grabs local admin Accounts
                    $AdminString = psexec -accepteula -nobanner \\$ServerName net localgroup $LocalGroup

                    # Notifies running user of status
                    Write-Host "Collecting Logon Events (ID = $LogonEventID) on `"$ServerName`"..." -ForegroundColor Magenta
                    # Collects logn events & returns values to string var
                    $FoldersPSExecString = psexec -accepteula -nobanner `
                        \\$ServerName powershell "&{$FolderPSExecScriptString}" | Where-Object $PSExecFolderFilter
                    
                    # Notifies running user of status
                    Write-Host "Collecting information on C:\Users folders on `"$ServerName`"..." -ForegroundColor Magenta
                    # Grabs folder names & modify/access timestamps & returns to string var
                    $EventPSExecString = psexec -accepteula -nobanner `
                        \\$ServerName powershell "&{$PSExecEventScriptString}" |
                            Where-Object $PsexecFolderFilter
                }

                ##########################################
                ### CREATE OBJECTS FROM PSEXEC STRINGS ###
                ##########################################

                # Converts AdminString to PSObject
                $PSExecLocalServerAdmins = $AdminString | Where-Object $LocalGroupFilter | ConvertFrom-Csv -Header 'Name'
                
                ### USER FOLDER OBJECTS ###
                # Creates a temp object to store parsed info
                $TempFolderObj = New-Object psobject -Property @{Ignore=$null}
                # Creates empty object for appending completed folder object groups
                $FoldersObj = @()
                # Loops through each string in the FoldersPSExecString array
                foreach($FolderString in $FoldersPSExecString)
                {
                    # RestartLoop bool for checking if new run needed when kicked to catch block
                    [bool]$RestartLoop = $false
                    # Will loop to add current property value to reset object if kicked to the catch block
                    do{
                        # Attempts to add a new NoteProperty to the object
                        try{
                            $TempFolderObj | 
                                Add-Member -MemberType NoteProperty -Name ($FolderString -replace '\s+\:\s+.*?$') `
                                    -Value ($FolderString -replace '^.*?\s+\:\s+') -ErrorAction Stop
                            
                            $RestartLoop = $false
                        }
                        # If cannot add Property, jumps to catch block, appends info to FoldersObj, & resets TempFolderObj
                        catch{
                            $FoldersObj += $TempFolderObj
                            $TempFolderObj = New-Object psobject -Property @{Ignore=$null}
                            $RestartLoop = $true
                        }
                    }while($RestartLoop)
                }
                # If value in TempFolderObj & not contained in FoldersObj, appends TempFolderObj value to FoldersObj
                if($TempFolderObj -and ($FoldersObj -notcontains $TempFolderObj))
                {$FoldersObj += $TempFolderObj}


                ### EVENT LOGS ###
                # Creates a temp object to store parsed info
                $TempEventObj = New-Object psobject -Property @{Ignore=$null}
                # Creates empty object for appending completed Event object groups
                $EventObj = @()
                # Declares empty string array & string for obj's Message property value
                [string[]]$MessageArray = $null
                [string]$MessageString = $null
                # Loops through each string in the FoldersPSExecString array
                foreach($EventSubstring in $EventPSExecString)
                {
                    # RestartLoop bool for checking if new run needed when kicked to catch block
                    [bool]$RestartLoop = $false
                    # Will loop to add current property value to reset object if kicked to the catch block
                    do{
                        # If the current loop string begins with Message or white space, 
                        #   adds the the Message property or appends to the existing MessageString
                        if($EventSubstring -match '^Message\s+\:' -or $EventSubstring -match '^\s+')
                        {
                            # Updates the Message Array with the current loop value & converts array to string
                            $MessageArray += $EventSubstring
                            $MessageString = [string]::join("`n",$MessageArray -replace '^Message\s+\:' -replace '^\s+')
                            
                            # If the tempEventObj has a Message property, updates the value
                            if($TempEventObj.Message)
                            {$TempEventObj.Message = $MessageString}
                            # If no Message property, adds property & MessageString as value
                            else{$TempEventObj | Add-Member -MemberType NoteProperty -Name 'Message' -Value $MessageString}

                            # Sets RestartLoop bool to false to exit do / while
                            $RestartLoop = $false
                        }
                        # All other strings that do not start with "Message" or white space are added as separate properties
                        else{
                            # Removes white space & sets property Name as value preceeding ':' with value after
                            try{
                                $TempEventObj | 
                                    Add-Member -MemberType NoteProperty -Name ($EventSubstring -replace '\s+\:\s+.*?$') `
                                        -Value ($EventSubstring -replace '^.*?\s+\:\s+') -ErrorAction Stop
                                # Sets RestartLoop bool to false to exit do / while
                                $RestartLoop = $false
                            }
                            # If the property already exists, Add-Member fails & jumps to the catch block
                            catch{
                                # Resets the MessageArray & MessageString if value exists
                                if($MessageArray)
                                {
                                    $MessageString = $null
                                    $MessageArray = @()
                                }
                                # Appends the TempEventObj to EventObj
                                $EventObj += $TempEventObj
                                # Resets the TempEventObj
                                $TempEventObj = New-Object psobject -Property @{Ignore=$null}
                                # Sets RestartLoop bool to true to restart do / while & add current loop property to Obj
                                $RestartLoop = $true
                            }
                        }
                    }while($RestartLoop)
                }
                # If value in TempEventObj & not contained in EventObj, appends TempEventObj value to EventObj
                if($TempEventObj -and ($EventObj -notcontains $TempEventObj))
                {$EventObj += $TempEventObj}

                # Creates a LoopObj w/parsed PSExec objects
                $LoopObj = New-Object PSObject -Property @{
                    LocalServerAdmins = $PSExecLocalServerAdmins
                    LogonEvents = $EventObj
                    UserFolders = $FoldersObj
                    PSComputerName = $ServerName
                }

                # Resets PSExec objects
                $PSExecLocalServerAdmins = @()
                $EventObj = @()
                $FoldersObj = @()
            }
############################################################################################################
###### END ### PSEXEC ### PSEXEC ###### PSEXEC ### PSEXEC ### PSEXEC ###### PSEXEC ### PSEXEC ### END ######
############################################################################################################

            #################################
            ### PARSES DATA FROM LOOP OBJ ###
            #################################
            if($LoopObj)
            {
                # Grabs LocalServerAdmins & removes everything before the \ in Name value (domain\user < removes 'domain\')
                $RemoteAdmins = $LoopObj.LocalServerAdmins.Name -replace '^.*?\\'
                # Sorts LogonEvents by TimeWritten so most recent are at top of list
                $RemoteLogonEvents = $LoopObj.LogonEvents | Sort-Object TimeWritten -Descending
                # Assigns UserFolders & UserFolderNames values
                $UserFolders = $LoopObj.UserFolders
                $UserFolderNames = $LoopObj.UserFolders.Name

                # Loops through each account returned in the RemoteAdmins array & runs the AppendReturnObject script against
                foreach($AdminAccount in $RemoteAdmins)
                {
                    $ReturnObject += &$AppendReturnObject -AdminAccount $AdminAccount `
                        -RemoteAdmins $RemoteAdmins -RemoteLogonEvents $RemoteLogonEvents `
                            -PingSucceeded $PingSucceeded -ServerName $LoopObj.PSComputerName `
                                -UserFolders $UserFolders
                }

                # Loops through each user folder in $UserFolderNames
                foreach($FolderName in $UserFolderNames)
                {    
                    # Resets EntryInReturnObj on each loop
                    $EntryInReturnObj = @()

                    # Checks to see if a value already exists in the ReturnObject for the current user
                    $EntryInReturnObj = $ReturnObject | 
                        Where-Object {($_.Server -eq $ServerName) -and ($_.UserOrGroup -eq $FolderName)}
                    
                    # If there is already a matching entry in the ReturnObj
                    if($EntryInReturnObj)
                    {
                        # Resets LastLogon, UserFolderFolderLastModified
                        $LastLogonEvent = @()
                        $UserFolderFolderLastModified = @()
                        [string]$AdminType = $null
                        [string[]]$MemberOfGroup = $null
                        
                        # Gets the newest logon event that matches the current loop Username in 'Message' value
                        $LastLogonEvent = $RemoteLogonEvents | 
                            Where-Object {$_.Message -match "\s+$FolderName"} | 
                                Select-Object -First 1
                                
                        # Looks at the LastWriteTime attribute on the user's C:\Users folder
                        $UserFolderFolderLastModified = ($UserFolders | 
                            Where-Object {$_.Name -eq $FolderName}).LastWriteTime
                        
                        # Updates existing object property values
                        $ReturnObject | Where-Object {$_ -eq $EntryInReturnObj} | 
                            ForEach-Object{
                                $_.LastLogonEvent = $LastLogonEvent.TimeWritten
                                $_.LastLogonEventID = $LastLogonEvent.InstanceID
                                $_.LastLogonEventIndex = $LastLogonEvent.Index
                                $_.LastLogonEventEntryType = $LastLogonEvent.EntryType
                                $_.UserFolderLastModified = $UserFolderFolderLastModified
                            }
                    }
                    # If no matching entry in ReturnObject, updates ReturnObject w/AppendReturnObject script
                    else{
                        $ReturnObject += &$AppendReturnObject -AdminAccount $FolderName `
                            -RemoteAdmins $RemoteAdmins -RemoteLogonEvents $RemoteLogonEvents `
                                -PingSucceeded $PingSucceeded -ServerName $LoopObj.PSComputerName `
                                    -UserFolders $UserFolders
                    }
                }
            }

            # Returns the Return Object for current loop server
            $ReturnObject
        }
        # If no response to ping, returned loop object is mostly null w/server name & failed ping status
        else{
            &$AppendReturnObject -ServerName $ServerName -PingSucceeded $PingSucceeded
        }
    }
}

#Psexec fails w/access denied running as std user; special characters cause issues when attempting to use cmdkey /add:<target> to resolve this
#https://stackoverflow.com/questions/828432/psexec-access-denied-errors
