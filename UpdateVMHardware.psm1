#Requires -Module VMware.VimAutomation.Core
#http://vcloud-lab.com/entries/powercli/using-powercli-to-increase-vmdk-virtual-disk--in-vmware-virtual-machine
function Update-VMHardware
{
    [alias('Update-VMSpecs')]
    param(
        [parameter(Mandatory=$true,Position=0)]
        [alias('Computer','VirtualMachine','VM','ServerName','Server')]
        [string]$VMName,

        [parameter(Mandatory=$false,Position=1)]
        [char]$DriveLetter,

        [parameter(Mandatory=$false,Position=2)]
        [alias('Storage')]
        [int]$DiskSize,

        [parameter(Mandatory=$false,Position=3)]
        [alias('Memory')]
        [int]$RAM,

        [parameter(Mandatory=$false,Position=4)]
        [alias('Credential')]
        [pscredential]$AdminCred,

        [switch]$Confirm,
        [switch]$WhatIf
    )

    #################
    ### SNAPSHOTS ###
    #################

    $Snapshot = Get-VM $VMName | Get-Snapshot
    if($Snapshot)
    {
        Write-Host "Snapshot(s) for the VM ($VMName) have been found:"
        $Snapshot | Select-Object VM, Name, Created | Out-Host

        do{
            switch((Read-Host -Prompt "Remove all snapshots for $VMName? (Y / N)").Substring(0,1))
            {
                y {
                    $ValidResponse = $true
                    $Snapshot | Remove-Snapshot -Confirm:$Confirm -WhatIf:$WhatIf
                }
                n {
                    $ValidResponse = $true
                    Write-Host "`nNo changes will be made to existing snapshots.`n"
                    Write-Warning "Changes to VM guest ($VMName) may fail due to existing snapshots."
                }

                default{
                    $ValidResponse = $false
                    Write-Warning "Invalid entry, please try again."
                }
            }
        }until($ValidResponse)
    }


    ###############
    ### STORAGE ###
    ###############

    #Checks if DriveLetter & DiskSpace params both have values - if not, prompts for value
    if($DriveLetter -and !$DiskSize){[int]$DiskSize = Read-Host -Prompt "Please enter a new disk size value (GB)"}
    if($DiskSize -and !$DriveLetter){[char]$DriveLetter = (Read-Host -Prompt "Please enter drive letter").Substring(0,1)}

    switch($DriveLetter)
    {
        C {
            $DriveChange = $true
            $DiskNumber = 1
        }
        
        D {
            $DriveChange = $true
            $DiskNumber = 2
        }
        
        {$_ -eq $null -or $_ -eq ''} {Write-Host "No drive changes specified - skipping" -ForegroundColor Yellow}
        
        default {
            $DriveChange = $true

            $VMAttachedStorage = Get-VM $VMName | Get-HardDisk | Select-Object Name,CapacityGB,FileName
            $HDDCount = ($VMAttachedStorage | Measure-Object).Count
            
            do{
                $VMAttachedStorage | Out-Host
                
                switch([int](Read-Host "Please specify which Hard Disk to resize (1 - $($HDDCount))"))
                {
                    {$_ -gt 0 -and $_ -le $HDDCount} {$DiskNumber = $_}
                    
                    default {
                        $DiskNumber = $null
                        Write-Warning "Invalid entry, please try again."
                    }
                }
            }until($DiskNumber)
        }
    }

    #If the VM's HDD is to be updated, performs actions in this block
    if($DriveChange)
    {
        #Gets the target VM's HDD as specified & sets the updated disk capacity (in GB)
        Get-VM $VMName | Get-HardDisk | Where-Object {$_.Name -match $DiskNumber} | 
            Set-HardDisk -CapacityGB $NewDiskCapacity -ErrorAction Stop `
                -Confirm:$Confirm -WhatIf:$WhatIf

        
        #Attempts to rescan drives & allocate newly available storage to target HDD
        try{
            #Defines a hashtable of parameters to pass to Invoke-Command
            $InvokeParams = @{
                ComputerName = $ServerName
                ArgumentList = $DriveLetter
            }
            #If AdminCred contains pscredential values, appends to the InvokeParams hash table
            if($AdminCred){$InvokeParams.Add('Credential',$AdminCred)}
            
            #Attempts to run Invoke-Command with the InvokeParams hash table property values
            Invoke-Command @InvokeParams -ScriptBlock {
                #Assigns value of variable passed in ArgumentList to DriveLetter var
                $DriveLetter = $args[0]
    
                #Outputs to console drive letter to be updated
                Write-Host "Drive letter is $DriveLetter"
                
                #Rescans HDDs to make expanded storage available
                Get-Disk | Update-Disk
                
                #Grabs HDD's current size & Maximum size available & assigns to the DiskResize & CurrentDiskSize vars
                $DiskInfo = (Get-Partition -DriveLetter $DriveLetter | ForEach-Object{
                    $CurrentSize = ($_.Size / 1GB)
                    $_ | Get-PartitionSupportedSize | Select-Object  SizeMax,
                        @{Name='CurrentSize';Expression={$CurrentSize}}})
    
                $DiskResize = $DiskInfo.SizeMax
                $CurrentDiskSize = $DiskInfo.CurrentSize
    
                #Writes to screen what the current disk size is & what the updated size will be
                Write-Host "Current size = $($CurrentDiskSize)GB`nMaximum disk size after rescan = $($DiskResize / 1GB)GB"
                #Gets specified partition & resizes to the maximul available value
                Get-Partition -DriveLetter $DriveLetter | Resize-Partition -Size $DiskResize -WhatIf:$WhatIf -Confirm:$Confirm
            }
        }
        #If Invoke-Command fails, attempts to establish RDP connection
        catch{
            #Notifies running user that Invoke-Command has failed (PSRemoting may be disabled)
            Write-Warning "Invoke-Command for disk resize on $ServerName has failed."
            #Notifies running user tha an interactive RDP connection is going to be attempted
            Write-Host "Interactive session for disk resize required - attempting to establish RDP connection." `
                -ForegroundColor Yellow
    
            #If no value in AdminCred, prompts for credentials
            if(!$AdminCred){$AdminCred = Get-Credential}
    
            #Assigns the Username & password values in AdminCred to the Username & Pass vars, respectively
            $Pass = $AdminCred.GetNetworkCredential().Password
            $Username = $AdminCred.UserName

            #Creates a new entry in Credential Manager & attempts RDP connection
            cmdkey /generic:$ServerName /user:$UserName /pass:$Pass
            mstsc /v:$ServerName

            #Pauses 3 seconds then prompts if RDP creds should be removed from Credential Manager
            timeout -t 3 > $null

            #Loops through prompt until a valid response is provided
            do{
                switch((Read-Host -Prompt "Remove RDP credentials for $ServerName from Credential Manager? (Y / N)").Substring(0,1))
                {
                    y {
                        $ValidResponse = $true
                        cmdkey /delete:$ServerName
                    }
                    
                    n {
                        $ValidResponse = $true
                        Write-Host "No changes have been made." -ForegroundColor Yellow
                    }

                    default {
                        $ValidResponse = $false
                        Write-Warning "Invalid response.  Please try again."
                    }
                }
            }until($ValidResponse)
        }
    }


    ##############
    ### MEMORY ###
    ##############

    #If a RAM value has been specified, attempts to update VM's memory allocation with provided value
    if($RAM)
    {
        try{
                #Attempts to update the VMs memory - will fail if MemoryHotPlug is not enabled
                Get-VM $VMName | 
                    Set-VM -MemoryGB $RAM -Confirm:$Confirm -WhatIf:$WhatIf -ErrorAction Stop
            }
        catch{
            #If Set-VM failed, warns running user
            Write-Warning "Updated memory allocation failed - MemoryHotPlug may be disabled on VM ($VMName)."

            #Prompts to shut down VM & retry changes
            do{
                switch((Read-Host -Prompt "Would you like to shut down VM ($VMName) to make changes?" ).Substring(0,1))
                {
                    #Shuts down VM & retries setting Memory allocation
                    y {
                        $ValidResponse = $true
                        Write-Host "Shutting down VM guest $VMName"
                        Get-VM $VMName | Shutdown-VMGuest -Confirm:$Confirm -WhatIf:$WhatIf

                        #Pauses script until the VM has successfully entered a 'PoweredOff' state
                        do{
                            Write-Host "Waiting for VM ($VMName) to power down fully..."
                            timeout -t 2 > $null
                        }until((Get-VM).PowerState -eq 'PoweredOff')

                        try{
                                Write-Host "Updating VM memory allocation..."
                                Get-VM $VMName | 
                                    Set-VM -MemoryGB $RAM -Confirm:$Confirm -WhatIf:$WhatIf -ErrorAction Stop
                            }
                        #If memory allocation fails after shutdown, warns that failed & manual maintenance will be needed
                        catch{
                            Write-Warning "Updated memory allocation failed."
                            Write-Host "Please schedule a maintenance window to manually perform memory reallocation." `
                                -ForegroundColor Yellow
                        }

                        #Brief timeout to ensure Set-VM completes successfully before moving on
                        timeout -t 3 > $null

                        #Restarts VM
                        Write-Host "Restarting VM guest $VMName"
                        Get-VM $VMName | Start-VM -Confirm:$Confirm -WhatIf:$WhatIf

                        #Pauses script until the VM has successfully entered a 'PoweredOn' state
                        do{
                            Write-Host "Waiting for VM ($VMName) to power on..."
                            timeout -t 2 > $null
                        }until((Get-VM).PowerState -eq 'PoweredOn')
                    }
                    #Makes no changes & notifies running user manual maintenance will be needed
                    n {
                        $ValidResponse = $true
                        Write-Warning "No changes have been made to VM's memory configuration."
                        Write-Host "Please schedule a maintenance window to manually perform memory reallocation." `
                            -ForegroundColor Yellow
                    }

                    #Invalid response - triggers do / until to loop again
                    default {
                        $ValidResponse = $false
                        Write-Warning "Invalid response, please try again."
                    }
                }
            }until($ValidResponse)
        }
    }
}
