function Enable-FolderInheritance
{
    [alias('Repair-FolderInheritance')]
    param(
        [string[]]$FolderPath,
        [switch]$Confirm,
        [switch]$WhatIf
    )

    ### LOGGING ###
    if(![bool](Get-Command 'Get-Timestamp' -ErrorAction Ignore))
    {Import-Module "$PSScriptRoot\LoggingTimestamp.psm1" -Force -Global}

    [int]$totalFolders = ($FolderPath | Measure-Object).Count
    [int]$loopNumber = 0

    foreach($folder in $FolderPath)
    {
        $loopNumber++
        Write-Progress -Activity "Repairing Inheritance" -Status "Processing folder `"$folder`"" `
            -PercentComplete (($loopNumber / $totalFolders) * 100)
        try{
            if(Test-Path $folder -ErrorAction Ignore)
            {
                Get-Timestamp -Message "Collecting permission information for folder `"$Folder`""
                # Grabs current permissions on current loop folder
                $ACL = Get-Acl $Folder
                # Sets inheritance values for ACL obj
                #   https://community.spiceworks.com/topic/post/7612099
                $ACL.SetAccessRuleProtection($false,$true)
                Get-Timestamp "$(if($WhatIf){'WhatIf'}else{'change'})" `
                    -Message "Enabling inheritance on folder `"$Folder`""
                # Only attempts ACL set if no WhatIf
                if(!$WhatIf)
                {
                    # Defines a hash table for splatting param values in Set-ACL cmd
                    $setAclHash = @{
                        Path        = $Folder
                        ACLObject   = $ACL
                        Confirm     = $Confirm
                        WhatIf      = $WhatIf
                    }
                    Set-Acl @setAclHash
                    Get-Timestamp 'success' -Message "Inheritance successfully enabled on folder `"$Folder`""
                }
            }
            else{throw "Folder path `"$folder`" not found"}
        }
        catch{
            Get-Timestamp 'error' -Message "Failed to set permission inheritance on folder `"$Folder`""
        }
    }
}
