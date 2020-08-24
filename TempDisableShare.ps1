param(
    [string[]]$ServerName = $env:COMPUTERNAME,
    [string]$ShareName,

    [pscredential]$Credential,

    [switch]$Confirm,
    [switch]$WhatIf,

    [switch]$Force = (&{if($WhatIf){$false}})
)

# Return object for share permissions
$ShareInfoReturnObj = @()

# Script block for closing connections & disabling share
$DisableShareBlock = {
    param(
        [string]$ShareName,
        [bool]$Confirm,
        [bool]$WhatIf,

        [bool]$Force
    )

    try{
        #Grabs the existing share's properties
        $ShareInfo = Get-SMBShare $ShareName -ErrorAction Stop
    }
    catch{$ShareInfo = $null}

    if($ShareInfo)
    {
        #Grabs the existing share's permissions
        $SharePermission = $ShareInfo | Get-SmbShareAccess | 
            Where-Object {$_.AccountName -notmatch '^BUILTIN'}
        #Groups each permission by type
        $SharePermissionGroup = $SharePermission | Group-Object AccessRight

        #######################
        # Notify running user #
        #######################
        $NameString = "### $($env:COMPUTERNAME) ###"
        [string]$Header = $null
        for([int]$i = 0; $i -lt $NameString.length; $i++){$Header += '#'}
        $CurrentLoop = "`n$Header`n$NameString`n$Header`n"
        Write-Host $CurrentLoop -ForegroundColor Magenta

        # Notifies running user closing open connections to share
        Write-Host "Closing open connections to $($ShareInfo.Path) on $env:COMPUTERNAME..." -ForegroundColor Cyan

        #Replaces \ with \\ for matching in Where-Object
        $ShareLocalPath = $ShareInfo.Path -replace '\\','\\'
        #Closes open shares
        Get-SMBOpenFile | Where-Object {$_.Path -match $ShareLocalPath} |
            Close-SmbOpenFile -WhatIf:$WhatIf -Confirm:$Confirm -Force:$Force | 
                Out-Host

        # Returns the share information
        New-Object PSObject -Property @{
            Server = $env:COMPUTERNAME
            ShareName = $ShareInfo.Name
            SharePath = $ShareInfo.Path
            FullAccess = ($SharePermissionGroup | Where-Object {$_.Name -eq 'Full'}).Group.AccountName
            ChangeAccess = ($SharePermissionGroup | Where-Object {$_.Name -eq 'Change'}).Group.AccountName
            ReadAccess = ($SharePermissionGroup | Where-Object {$_.Name -eq 'Read'}).Group.AccountName
        }

        # Notifies running user removing SMB share
        Write-Host "Disabling SMB share $ShareName ($($ShareInfo.Path)) on $env:COMPUTERNAME..." -ForegroundColor Cyan

        #Disables smb share
        Remove-SmbShare $ShareInfo.Name -WhatIf:$WhatIf -Confirm:$Confirm -Force:$Force | Out-Host
    }
}

$EnableShareBlock = {
    param(
        [string]$ShareName,
        [string]$SharePath,
        [string[]]$FullAccess,
        [string[]]$ChangeAccess,
        [string[]]$ReadAccess,

        [bool]$WhatIf,
        [bool]$Confirm
    )

    $SmbShareHash = @{
        Name = $ShareName
        Path = $SharePath
        Confirm = $Confirm
        WhatIf = $WhatIf
    }
    if($FullAccess){$SmbShareHash.FullAccess = $FullAccess}
    if($ChangeAccess){$SmbShareHash.ChangeAccess = $ChangeAccess}
    if($ReadAccess){$SmbShareHash.ReadAccess = $ReadAccess}
    
    # WhatIf doesn't seem to work with New-SMBShare, so creates a string to output to the console if WhatIf used
    if($WhatIf)
    {
        [string]$WhatIfString = $null
        $WhatIfString += $SmbShareHash.GetEnumerator().Name | ForEach-Object{
            $Name = $_
            "-$Name $($SmbShareHash."$_")"
        }
        
        Write-Host "What If:  New-SMBShare $WhatIfString"
    }
    # If no WhatIf performs the share re-enable
    else{New-SmbShare @SmbShareHash}
}

#If the server specified is the current machine, runs script locally
if($ServerName -contains $env:COMPUTERNAME)
{
    #Since switches are wonky in script blocks, WhatIf & Confirm are bools, so no ':'
    $ShareInfoReturnObj += &$DisableShareBlock -ShareName $ShareName -Confirm $Confirm -WhatIf $WhatIf -Force $Force
}


#Hash table for splatting
$DisableInvokeHash = @{
    ComputerName = $ServerName
    Command = $DisableShareBlock
    ArgumentList = ($ShareName, $Confirm, $WhatIf, $Force)
}
if($Credential){$DisableInvokeHash.Credential = $Credential}

#Runs command against remote server w/hash table parameter values
$ShareInfoReturnObj += Invoke-Command @DisableInvokeHash |
    Select-Object Server, ShareName, SharePath, FullAccess, ChangeAccess, ReadAccess


$ShareInfoReturnObj | Format-Table | Out-Host

# Notifies user pausing to allow changes before re-enabling shares
$PauseString = "
################################################
### PAUSED - PRESS ENTER TO RE-ENABLE SHARES ###
################################################
`n"

Write-Host $PauseString -ForegroundColor Yellow

# Pauses pipeline until enter key pressed
pause

foreach($NetworkShare in $ShareInfoReturnObj)
{
    $EnableInvokeHash = @{
        ComputerName = $NetworkShare.Server
        Command = $EnableShareBlock
        ArgumentList = ($NetworkShare.ShareName, $NetworkShare.SharePath, $NetworkShare.FullAccess, 
            $NetworkShare.ChangeAccess, $NetworkShare.ReadAccess, $WhatIf, $Confirm)
    }
    if($Credential){$EnableInvokeHash.Credential = $Credential}

    if($NetworkShare.Server -eq $env:COMPUTERNAME)
    {
        &$EnableShareBlock -ShareName $NetworkShare.ShareName -SharePath $NetworkShare.SharePath `
            -FullAccess $NetworkShare.FullAccess -ChangeAccess $NetworkShare.ChangeAccess `
                -ReadAccess $NetworkShare.ReadAccess -WhatIf $WhatIf -Confirm $Confirm
    }
    else{Invoke-Command @EnableInvokeHash | Out-Host}
}
